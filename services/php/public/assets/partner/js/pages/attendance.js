(() => {
    'use strict';
    const H = window.HappyPartner;

    H.registerPage(() => {
        const app = document.getElementById('attendanceApp');
        if (!app) return;

        const link = new URL(app.dataset.scanPath, window.location.origin).href;
        const qrBox = document.getElementById('attQr');
        const note = document.getElementById('attQrNote');

        // The QR image is drawn in the browser (nothing about the link leaves this page).
        function drawQr() {
            if (typeof window.qrcode !== 'function') {
                note.hidden = false;
                note.textContent = 'QR আঁকার লাইব্রেরি পাওয়া যায়নি। নিচের লিংকটি কপি করে অন্য QR টুলে ব্যবহার করুন: ' + link;
                return;
            }
            const qr = window.qrcode(0, 'M');
            qr.addData(link);
            qr.make();
            qrBox.innerHTML = qr.createSvgTag({ cellSize: 6, margin: 4, scalable: true });
        }
        if (typeof window.qrcode === 'function') {
            drawQr();
        } else {
            // vendor/qrcode/qrcode.js (qrcode-generator) is loaded only on this page
            const tag = document.createElement('script');
            tag.src = H.url('/assets/vendor/qrcode/qrcode.js');
            tag.onload = drawQr;
            tag.onerror = drawQr;
            document.head.appendChild(tag);
        }

        document.getElementById('attCopyBtn')?.addEventListener('click', async () => {
            try {
                await navigator.clipboard.writeText(link);
                H.showToast('লিংক কপি হয়েছে।');
            } catch {
                window.prompt('লিংকটি কপি করুন:', link);
            }
        });

        document.getElementById('attPrintBtn')?.addEventListener('click', () => {
            const svg = qrBox.innerHTML;
            const w = window.open('', '_blank');
            if (!w) { H.showToast('প্রিন্ট উইন্ডো খোলা যায়নি — পপ-আপ অনুমতি দিন।'); return; }
            w.document.write(`<!doctype html><meta charset="utf-8"><title>হাজিরা QR</title>
                <style>body{font-family:sans-serif;text-align:center;margin:40px}svg{width:360px;height:360px}h1{font-size:26px}p{color:#555;font-size:16px}</style>
                <h1>হাজিরা — QR স্ক্যান করুন</h1>${svg}<p>আসার সময় এই QR স্ক্যান করুন</p>`);
            w.document.close();
            w.focus();
            setTimeout(() => w.print(), 300);
        });

        document.getElementById('attRegenBtn')?.addEventListener('click', (e) => {
            if (!window.confirm('নতুন QR তৈরি করলে আগের ছাপানো QR আর কাজ করবে না। নিশ্চিত?')) return;
            H.submitAction(e.currentTarget, null, 'তৈরি হচ্ছে…', () => H.api('POST', H.url('/partner/attendance/regenerate')));
        });

        const form = document.getElementById('attSettingsForm');
        document.getElementById('attUseHereBtn')?.addEventListener('click', (e) => {
            const btn = e.currentTarget;
            if (!navigator.geolocation) { H.formError(form, 'এই ব্রাউজারে লোকেশন সুবিধা নেই।'); return; }
            H.formError(form, '');
            btn.disabled = true;
            navigator.geolocation.getCurrentPosition((pos) => {
                btn.disabled = false;
                form.elements.lat.value = pos.coords.latitude.toFixed(7);
                form.elements.lng.value = pos.coords.longitude.toFixed(7);
                form.requestSubmit();
            }, () => {
                btn.disabled = false;
                H.formError(form, 'লোকেশন পাওয়া যায়নি। ব্রাউজারে লোকেশনের অনুমতি দিন।');
            }, { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 });
        });

        form?.addEventListener('submit', (e) => {
            e.preventDefault();
            const f = form.elements;
            H.submitAction(form.querySelector('button[type="submit"]'), form, 'সংরক্ষণ হচ্ছে…', () => H.api('POST', H.url('/partner/attendance/settings'), {
                lat: f.lat.value, lng: f.lng.value, radius: f.radius.value, duty_start: f.duty_start.value,
            }));
        });
    });
})();
