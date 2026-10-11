import unittest
from fastapi import HTTPException
from pydantic import ValidationError
from app.api.profile import ProfileUpdate, image_bytes
import base64
class ProfileTests(unittest.TestCase):
 def test_identity_and_role_cannot_be_supplied(self):
  with self.assertRaises(ValidationError): ProfileUpdate(telefono='+56912345678',rol_id='other',id='other')
 def test_phone_validation(self):
  self.assertEqual(ProfileUpdate(telefono=' +56912345678 ').telefono,'+56912345678')
  with self.assertRaises(ValidationError): ProfileUpdate(telefono='invalid')
 def test_active_content_rejected(self):
  with self.assertRaises(HTTPException): image_bytes(base64.b64encode(b'<svg></svg>').decode())
 def test_malformed_base64_rejected(self):
  with self.assertRaises(HTTPException): image_bytes('not base64!')
