#!/usr/bin/env python3
"""লাইসেন্স কী তৈরি: python3 tools/new_license.py pro 365 "গ্রাহকের নাম"
আউটপুট JSON টি Firebase Console > Realtime Database > licenses নোডে Import JSON করুন
(অথবা নোড হাতে বানিয়ে plan, expiry, customer লিখুন)।"""
import sys, json, secrets, datetime
plan = sys.argv[1] if len(sys.argv) > 1 else 'basic'      # basic | pro | enterprise
days = int(sys.argv[2]) if len(sys.argv) > 2 else 30
cust = sys.argv[3] if len(sys.argv) > 3 else ''
A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
key = 'SSH-' + '-'.join(''.join(secrets.choice(A) for _ in range(4)) for _ in range(2))
exp = (datetime.date.today() + datetime.timedelta(days=days)).isoformat()
print('KEY   :', key)
print(json.dumps({key: {'plan': plan, 'expiry': exp, 'customer': cust}}, ensure_ascii=False, indent=2))
