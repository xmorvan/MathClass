"""
data_deletion.py
Deleting data, as promised in docs/legal/politique-confidentialite.md.

  - delete_class: a teacher deletes one of their classes. Everything that
    belongs to it goes: the class document and its subcollections
    (students, level progress, groups, chapters), its assignments and
    periods, its submissions, and the students' handwriting images.
  - delete_account: a teacher deletes their account (required by App Store
    guideline 5.1.1(v)). All their classes as above, their exercise library
    and its images, their profile, then their Firebase Auth user.
  - purge_old_submissions: scheduled daily. Submissions and their images
    older than RETENTION_DAYS are deleted.

Clients cannot do this themselves: the security rules only allow deleting
single documents, and Firestore does not cascade.
"""

from __future__ import annotations

import datetime

from firebase_functions import https_fn

import auth_guard

RETENTION_DAYS = 365
_PAGE = 300


def _bucket():
    import firebase_admin
    from firebase_admin import storage

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    return storage.bucket()


def _delete_blob(bucket, path) -> None:
    if isinstance(path, str) and path and not path.startswith("http"):
        blob = bucket.blob(path)
        if blob.exists():
            blob.delete()


def _delete_query(db, query, bucket=None, image_field=None) -> int:
    """Delete every document matched by `query` (recursively), page by page."""
    deleted = 0
    while True:
        page = list(query.limit(_PAGE).stream())
        if not page:
            return deleted
        for snapshot in page:
            if bucket is not None and image_field:
                _delete_blob(bucket, (snapshot.to_dict() or {}).get(image_field))
            db.recursive_delete(snapshot.reference)
            deleted += 1


def _delete_class_data(db, bucket, class_id: str) -> None:
    for collection in ("assignments", "periods"):
        _delete_query(db, db.collection(collection).where("classID", "==", class_id))
    _delete_query(
        db,
        db.collection("submissions").where("classID", "==", class_id),
        bucket=bucket,
        image_field="pngURL",
    )
    for blob in list(bucket.list_blobs(prefix=f"submissions/{class_id}/")):
        blob.delete()
    db.recursive_delete(db.collection("classes").document(class_id))


def _require_class_owner(db, uid: str, class_id) -> str:
    if not isinstance(class_id, str) or not class_id or "/" in class_id:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'classID' est requis.",
        )
    snapshot = db.collection("classes").document(class_id).get()
    if not snapshot.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Classe introuvable.",
        )
    if (snapshot.to_dict() or {}).get("teacherID") != uid:
        raise auth_guard._denied()
    return class_id


def delete_class_handler(req: https_fn.CallableRequest) -> dict:
    uid = auth_guard.require_teacher(req)
    db = auth_guard._get_firestore()
    class_id = _require_class_owner(db, uid, (req.data or {}).get("classID"))
    _delete_class_data(db, _bucket(), class_id)
    return {"deleted": class_id}


def delete_account_handler(req: https_fn.CallableRequest) -> dict:
    uid = auth_guard.require_teacher(req)
    db = auth_guard._get_firestore()
    bucket = _bucket()

    class_ids = [
        s.id for s in db.collection("classes").where("teacherID", "==", uid).stream()
    ]
    for class_id in class_ids:
        _delete_class_data(db, bucket, class_id)

    # Submissions stamped with this teacher but whose class is already gone.
    _delete_query(
        db,
        db.collection("submissions").where("teacherID", "==", uid),
        bucket=bucket,
        image_field="pngURL",
    )
    _delete_query(
        db,
        db.collection("exercises").where("teacherID", "==", uid),
        bucket=bucket,
        image_field="statementImageURL",
    )
    db.recursive_delete(db.collection("users").document(uid))

    from firebase_admin import auth

    auth.delete_user(uid)
    return {"deletedClasses": len(class_ids)}


def purge_old_submissions(now: datetime.datetime | None = None) -> int:
    """Delete submissions (and their images) older than RETENTION_DAYS."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    cutoff = now - datetime.timedelta(days=RETENTION_DAYS)
    db = auth_guard._get_firestore()
    return _delete_query(
        db,
        db.collection("submissions").where("timestamp", "<", cutoff),
        bucket=_bucket(),
        image_field="pngURL",
    )
