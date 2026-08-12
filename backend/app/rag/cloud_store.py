"""
التخزين السحابي الدائم — S3-compatible (يدعم Supabase Storage وCloudflare R2
وأي مزوّد متوافق مع S3 عبر boto3).

قرص Render المجاني مؤقت (يُمحى عند إعادة النشر/التشغيل)، لذلك تُرفع ملفات
المستخدمين إلى السحابة وتُستعاد تلقائياً عند كل بدء.

مفعّل فقط عند ضبط المتغيرات (Supabase مثالاً):
  STORAGE_ENDPOINT          → https://<project_ref>.supabase.co/storage/v1/s3
  STORAGE_ACCESS_KEY_ID     → Access Key ID (من إعدادات التخزين)
  STORAGE_SECRET_ACCESS_KEY → Secret Access Key
  STORAGE_BUCKET            → اسم الـ bucket
  STORAGE_REGION            → اختياري، افتراضياً "us-east-1"

بدونها يعمل الخادم بالسلوك السابق (قرص محلي) دون أي خطأ.
"""

import os
from typing import List, Optional


class CloudStore:
    def __init__(self):
        self.endpoint = os.getenv("STORAGE_ENDPOINT", "").strip()
        self.access_key = os.getenv("STORAGE_ACCESS_KEY_ID", "").strip()
        self.secret_key = os.getenv("STORAGE_SECRET_ACCESS_KEY", "").strip()
        self.bucket = os.getenv("STORAGE_BUCKET", "").strip()
        self.region = os.getenv("STORAGE_REGION", "us-east-1").strip()
        self.enabled = bool(
            self.endpoint and self.access_key and self.secret_key and self.bucket
        )

    def _client(self):
        import boto3
        from botocore.config import Config

        session = boto3.session.Session()
        return session.client(
            "s3",
            endpoint_url=self.endpoint,
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
            region_name=self.region,
            config=Config(s3={"addressing_style": "path"}),
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
        """إرجاع أسماء ملفات المستخدم في السحابة."""
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
