# SmartStoreHub 🛒
সুপার শপের জন্য আধুনিক POS ও ম্যানেজমেন্ট অ্যাপ (Flutter, অফলাইন-ফার্স্ট) — **Powered by Hasan**

## ফিচার (v1.0)
- ৩ রোল: এডমিন (মালিক) / ম্যানেজার / ক্যাশিয়ার — আলাদা লগইন ও আলাদা অ্যাক্সেস
- POS বিলিং: বারকোড স্ক্যান, ডিসকাউন্ট, নগদ/বিকাশ/নগদ/কার্ড/বাকি, রসিদ শেয়ার (WhatsApp ইত্যাদি)
- ইনভেন্টরি: স্টক সতর্কতা, মেয়াদ সতর্কতা, অটো বারকোড তৈরি ও লেবেল
- বাকি-বকেয়া খাতা: আদায়, রিমাইন্ডার শেয়ার
- ড্যাশবোর্ড ও রিপোর্ট: দৈনিক/৭/৩০ দিন, লাভ, সেরা পণ্য, কর্মী অনুযায়ী বিক্রি
- সরবরাহকারী ও ক্রয় এন্ট্রি (স্টক অটো বাড়ে), ব্যাকআপ রিস্টোর, ডার্ক মোড
- ইউজার ম্যানেজমেন্ট, পাসওয়ার্ড (SHA-256 হ্যাশ), অ্যাক্টিভিটি লগ, ব্যাকআপ
- মাল্টি-শাখা কাঠামো প্রস্তুত (সব টেবিলে `company_id`, `branch_id`)

## লাইসেন্স সিস্টেম (v1.1)
- ১৪ দিন ফ্রি ট্রায়াল → শেষে অ্যাপ লক → লাইসেন্স কী দিলে চালু
- কী একটি ডিভাইসে বাঁধা থাকে; মেয়াদ/প্ল্যান (basic=৩ ইউজার, pro=১০, enterprise=সীমাহীন) Firebase থেকে আসে
- অফলাইনে ১৪ দিন পর্যন্ত চলে; এরপর ইন্টারনেটে যাচাই লাগে
- **Firebase Rules:** `firebase_rules.json` এর কোড Realtime Database > Rules এ পেস্ট করে Publish করুন (এটি না করলে যে কেউ নকল লাইসেন্স বানাতে পারবে)
- নতুন কী: `python3 tools/new_license.py pro 365 "গ্রাহক"` → আউটপুট Firebase Console থেকে `licenses` নোডে Import JSON
- বাতিল করতে `revoked: true` বসান; ডিভাইস বদলাতে `device` নোড মুছুন
- `lib/core/license.dart` এ `kContact` এ নিজের নম্বর বসান

## প্রথম লগইন
`admin` / `admin123` — **লগইনের পরই পাসওয়ার্ড বদলান** (আরও → প্রোফাইল)।

## GitLab থেকে APK
1. GitLab-এ `SmartStoreHub` নামে নতুন প্রজেক্ট খুলুন
2. এই ফোল্ডারের সব ফাইল পুশ করুন (`git add . && git commit -m "init" && git push`)
3. **Build → Pipelines** এ `build_apk` শেষ হলে **Artifacts → Download** থেকে `SmartStoreHub.apk` নিন

## লোকালি বিল্ড
```
flutter create --platforms=android --project-name smartstorehub .
flutter pub get && dart run flutter_launcher_icons
# AndroidManifest.xml এ CAMERA permission যোগ করুন
flutter build apk --release
```

## রোডম্যাপ (বিক্রির জন্য)
ক্লাউড সিঙ্ক • ব্লুটুথ থার্মাল প্রিন্টার • ইংরেজি ভাষা • White-label
