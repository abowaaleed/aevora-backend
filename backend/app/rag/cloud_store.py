"""
Cloudflare R2 object storage — التخزين الدائم للملفات.

قرص Render المجاني مؤقت (يُمحى عند إعادة النشر/التشغيل)، لذلك تُرفع ملفات
المستخدمين إلى R2 (مجاني 10GB، بدون رسوم نقل) وتُستعاد تلقائياً عند كل بدء.

مفعّل فقط عند ضبط المتغيرات الأربعة:
  R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
بدونها يعمل الخادم بالسلوك السابق (قرص محلي) دون أي خطأ.
"""

import os
from typing import List, Optional


class CloudStore:
    def __init__(self):
        self.account_id = os.getenv("R2_ACCOUNT_ID", "").strip()
        self.access_key = os.getenv("R2_ACCESS_KEY_ID", "").strip()
        self.secret_key = os.getenv("R2_SECRET_ACCESS_KEY", "").strip()
        self.bucket = os.getenv("R2_BUCKET", "").strip()
        self.enabled = bool(
            self.account_id and self.access_key and self.secret_key and self.bucket
        )

    def _client(self):
        import boto3

        session = boto3.session.Session()
        return session.client(
            "s3",
            endpoint_url=f"https://{self.account_id}.r2.cloudflarestorage.com",
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
            region_name="auto",
        )

    @staticmethod
    def _key(uid: str, filename: str) -> str:
        return f"users/{uid}/uploads/{filename}"

    def upload(self, uid: str, filename: str, data: bytes) -> bool:
        """رفع ملف (best-effort). يرجع True عند النجاح."""
        if not self.enabled or not uid:
            return False
        try:
            self._client().put_object(
                Bucket=self.bucket, Key=self._key(uid, filename), Body=data
            )
            return True
        except Exception as e:
            print(f"[CLOUD STORE] upload failed for {filename}: {e}")
            return False

    def download(self, uid: str, filename: str) -> Optional[bytes]:
        if not self.enabled or not uid:
            return None
        try:
            obj = self._client().get_object(
                Bucket=self.bucket, Key=self._key(uid, filename)
            )
            return obj["Body"].read()
        except Exception as e:
            print(f"[CLOUD STORE] download failed for {filename}: {e}")
            return None

    def delete(self, uid: str, filename: str) -> bool:
        if not self.enabled or not uid:
            return False
        try:
            self._client().delete_object(
                Bucket=self.bucket, Key=self._key(uid, filename)
            )
            return True
        except Exception as e:
            print(f"[CLOUD STORE] delete failed for {filename}: {e}")
            return False

    def list(self, uid: str) -> List[str]:
        """إرجاع أسماء ملفات المستخدم في R2."""
        if not self.enabled or not uid:
            return []
        try:
            client = self._client()
            prefix = f"users/{uid}/uploads/"
            names: List[str] = []
            paginator = client.get_paginator("list_objects_v2")
            for page in paginator.paginate(Bucket=self.bucket, Prefix=prefix):
                for obj in page.get("Contents", []):
                    key = obj["Key"]
                    if key.startswith(prefix):
                        names.append(key[len(prefix):])
            return names
        except Exception as e:
            print(f"[CLOUD STORE] list failed for uid {uid}: {e}")
            return []


_cloud_store = CloudStore()


def get_cloud_store() -> CloudStore:
    return _cloud_store
