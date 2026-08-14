import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

// بدّل عنوان بوابة الدفع والمفاتيح السرية عند النشر.
// لا تُنشر هذه الملفات في التطبيق أبداً — تبقى على الخادم.
const GATEWAY = process.env.PAYMENT_GATEWAY || 'tap';
const TAP_SECRET_KEY = process.env.TAP_SECRET_KEY || 'sk_test_XXXX';
const TAP_WEBHOOK_TOKEN = process.env.TAP_WEBHOOK_TOKEN || '';

admin.initializeApp();

const db = admin.firestore();

// أسعار الخطط بالريال السعودي (شهرياً).
const PRICES: Record<string, { amount: number; currency: string }> = {
  premium: { amount: 29, currency: 'SAR' },
  managed: { amount: 49, currency: 'SAR' },
};

const PLAN_MONTHS = 1;

interface CheckoutBody {
  tier?: string;
  uid?: string;
  email?: string;
  successUrl?: string;
  cancelUrl?: string;
}

/** إنشاء جلسة دفع عبر Tap وإرجاع رابط صفحة الدفع للمستخدم. */
export const createCheckout = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'POST only' });
    return;
  }

  const body = req.body as CheckoutBody;
  const tier = body.tier || '';
  const uid = body.uid || '';
  const email = body.email || '';

  const price = PRICES[tier];
  if (!price) {
    res.status(400).json({ error: 'خطة غير معروفة' });
    return;
  }
  if (!uid) {
    res.status(400).json({ error: 'uid مطلوب' });
    return;
  }

  // مرجع فريد للاشتراك يظهر في webhook فيُكتب على Firestore.
  const reference = `${tier}_${uid}`;
  const redirectUrl = (body.successUrl || '').split('?')[0];

  try {
    const tapRes = await fetch('https://api.tap.company/v2/checkouts', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(TAP_SECRET_KEY + ':').toString('base64')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: price.amount,
        currency: price.currency,
        customer: {
          first_name: email.split('@')[0] || 'مستخدم',
          email,
          reference: uid,
        },
        source: { id: 'src_all' },
        reference,
        description: `اشتراك ايفورا — ${tier} (${price.amount} ${price.currency})`,
        metadata: { tier, uid },
        redirect: {
          url: redirectUrl,
          success_url: body.successUrl || redirectUrl,
          cancel_url: body.cancelUrl || redirectUrl,
        },
        save_card: false,
      }),
    });

    const data: any = await tapRes.json();
    const url = data?.transaction?.url;
    if (!url) {
      res.status(502).json({ error: 'تعذر إنشاء صفحة الدفع', details: data });
      return;
    }

    // تسجيل نية الاشتراك قبل الدفع لربط webhook بالحساب.
    await db.collection('subscriptions').doc(reference).set({
      tier,
      uid,
      email,
      provider: GATEWAY,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ url });
  } catch (e: any) {
    res.status(502).json({ error: e.message });
  }
});

/** استقبال حدث من Tap بعد الدفع وتفعيل الخطة في Firestore. */
export const handleWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).end();
    return;
  }
  // تحقق بسيط من صاحب الحدث (ضبط TAP_WEBHOOK_TOKEN في Tap Dashboard).
  const token = (req.headers['x-tap-token'] as string) || '';
  if (TAP_WEBHOOK_TOKEN && token !== TAP_WEBHOOK_TOKEN) {
    res.status(401).json({ error: 'unauthorized' });
    return;
  }

  const event = req.body as {
    type?: string;
    object?: any;
    reference?: { transaction?: string };
  };
  const type = event?.type || '';
  // tap يرسل إشارة الدفع عبر هذا النوع عادة.
  const approved =
    type === 'payment.captured' ||
    type === 'charge.approved' ||
    type === 'authorization.approved';

  if (!approved) {
    res.json({ received: true });
    return;
  }

  // البحث عن الاشتراك المعلق عبر reference المرسَل في الجلسة.
  const pending = await db
    .collection('subscriptions')
    .where('status', '==', 'pending')
    .get();

  const body = JSON.stringify(event);
  const match = pending.docs.find(
    (d) => d.data().tier && body.includes((d.data().email as string) || ''),
  );

  // مطابقة عبر البريد الإلكتروني المخزن في الحدث.
  const chargedEmail = String(
    (event?.object?.customer?.email as string) || event?.object?.email || '',
  ).toLowerCase();
  const doc = pending.docs.find(
    (d) => String(d.data().email || '').toLowerCase() === chargedEmail,
  );
  const sub = doc || match;

  if (!sub) {
    res.status(404).json({ error: 'لا يوجد اشتراك معلق مطابق' });
    return;
  }

  const data = sub.data();
  const tier = data.tier as string;
  const uid = data.uid as string;
  const endsAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + PLAN_MONTHS * 30 * 24 * 60 * 60 * 1000,
  );

  // تفعيل الخطة على مستند المستخدم — يقرؤه التطبيق عبر PlanStore.
  await db.collection('users').doc(uid).set(
    {
      plan: {
        tier,
        active: true,
        provider: GATEWAY,
        endsAt: endsAt.toMillis(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    },
    { merge: true },
  );
  await db
    .collection('subscriptions')
    .doc(sub.id)
    .update({ status: 'active', activatedAt: admin.firestore.FieldValue.serverTimestamp() });

  res.json({ received: true, activated: uid });
});

/** إلغاء اشتراك مفعّل (يوقف امتيازاته بعد نهاية المدة). */
export const cancelSubscription = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  const uid = (req.body?.uid || '') as string;
  if (!uid) {
    res.status(400).json({ error: 'uid مطلوب' });
    return;
  }
  await db
    .collection('users')
    .doc(uid)
    .set({ plan: { active: false, provider: GATEWAY } }, { merge: true });
  res.json({ cancelled: true });
});
