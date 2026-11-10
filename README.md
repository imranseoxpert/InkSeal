# InkSeal

A native macOS document-signing app (SwiftUI + PDFKit), similar in spirit to DocuSign / Documenso, that runs entirely on your Mac.

## Download

Get the latest **InkSeal-x.y.dmg** from the [Releases page](https://github.com/imranseoxpert/InkSeal/releases/latest). It's a universal app that runs on Apple Silicon and Intel Macs with macOS 14 Sonoma or later.

1. Open the DMG and drag **InkSeal** into **Applications**.
2. Open InkSeal. Because the app isn't notarized by Apple yet, macOS blocks it the first time.
3. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the InkSeal message. Confirm, and InkSeal opens. You only need to do this once.

   If you prefer Terminal: `xattr -dr com.apple.quarantine /Applications/InkSeal.app`

## Build from source

```bash
./build.sh        # universal app → build/InkSeal.app
./make_dmg.sh     # app + installer → dist/InkSeal-<version>.dmg
```

Needs macOS 14+ and either Xcode or the Command Line Tools. Use `ARCHS=arm64 ./build.sh` for a faster single-architecture build.

## Features

- **Create documents**: write from scratch or start from templates (Mutual NDA, Services Agreement, Offer Letter, Lease, Bill of Sale), with signature blocks generated per party. You can also import any PDF (⌘O or drag and drop).
- **Prepare**: add recipients in signing order (signer, approver or CC), then drag Signature, Initials, Name, Email, Date Signed, Text and Checkbox fields onto the page. Fields can be moved, resized, set as required or optional, and duplicated.
- **Sign**: type (several handwriting styles), draw, or upload a signature. Includes an e-sign disclosure, a guided "Next Field" button, a saved profile signature, and Decline.
- **Seal**: when the last signer finishes, values are burned into a new PDF and a **Certificate of Completion** is appended (recipients, signatures, full audit trail, SHA‑256 fingerprint of the original).
- **Track**: Drafts, Waiting, Completed and Voided lists, a per-document activity timeline, and Verify Integrity (re-hashes the files).
- **Deliver**: Export PDF, Share, open a Mail draft with the PDF attached, or Open in Preview.
- **Templates**: save any document as a reusable template with roles and fields.

## How signing works

Signing is **in person on this Mac** (host signing): each recipient signs in turn using "Sign as …". Email opens a Mail draft with the PDF for review. There is no server, so remote recipients can't sign from their own devices.

## Data

Stored in `~/Library/Application Support/InkSeal/`: `library.json` holds metadata, fields and audit trails, and `Documents/<id>/original.pdf` and `completed.pdf` hold the files. Set `INKSEAL_LIBRARY=/some/folder` to use a different library (useful for testing).

> Templates are starting points, not legal advice. Check e-signature requirements for your jurisdiction.
