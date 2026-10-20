// GET /account-deletion: the public page Google Play requires for apps that let users create an
// account. It says how to delete an account in the app, and how to ask for deletion without the
// app (by email to PRIVACY_CONTACT_EMAIL). Its URL goes into Play Console's Data safety form and
// docs/store/review-notes.md. English and Amharic; the Amharic text needs a native speaker's review
// (the same review as app_am.arb). What deletion removes matches docs/legal/privacy-policy.md §5.
import { Hono } from "hono";
import type { AppEnv } from "../env";
import { ApiError } from "../lib/errors";

export const accountDeletion = new Hono<AppEnv>();

const CACHE_SECONDS = 3600;
const SUBJECT = "Delete my Yeman Zefen account";

const escapeHtml = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

export function accountDeletionPage(email: string): string {
  const mail = escapeHtml(email);
  const href = `mailto:${escapeHtml(encodeURIComponent(email).replace(/%40/g, "@"))}?subject=${encodeURIComponent(SUBJECT)}`;
  const link = `<a href="${href}">${mail}</a>`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Delete your account · Yeman Zefen</title>
<style>
  body { font-family: system-ui, "Noto Sans Ethiopic", sans-serif; max-width: 40rem; margin: 0 auto; padding: 1.5rem 1rem; line-height: 1.55; color: #1a1a1a; background: #fff; }
  h1 { font-size: 1.5rem; } h2 { font-size: 1.15rem; margin-top: 1.75rem; }
  section + section { border-top: 1px solid #ddd; margin-top: 2rem; padding-top: 1rem; }
  a { color: #0b57d0; }
</style>
</head>
<body>
<section lang="en">
<h1>Delete your Yeman Zefen account</h1>
<h2>In the app</h2>
<p>Open <strong>Settings › Account › Delete account</strong>. If you have not signed in recently, the app asks you to sign in again first.</p>
<h2>Without the app</h2>
<p>Email ${link} with the subject “${SUBJECT}”, from the email address of your account. If you signed in with Google or Apple, say which. We delete the account within 30 days and reply to confirm.</p>
<h2>What is deleted</h2>
<p>Your sign-in account, your display name and your leaderboard scores. Your game sessions are kept with nothing that links them to you, because the play counts we report to the music association are built from them. Moderation records about an account are kept as described in our privacy policy.</p>
<h2>Played as a guest?</h2>
<p>If you never signed in, nothing on our side is linked to your name or email. Use <strong>Delete account</strong> in the app, or delete the app.</p>
</section>
<section lang="am">
<h1>የየማን ዘፈን መለያዎን ይሰርዙ</h1>
<h2>በመተግበሪያው</h2>
<p><strong>ቅንብሮች › መለያ › መለያ ይሰርዙ</strong> የሚለውን ይክፈቱ። በቅርቡ ካልገቡ መጀመሪያ እንደገና እንዲገቡ ይጠየቃሉ።</p>
<h2>ያለ መተግበሪያው</h2>
<p>መለያዎ ከተመዘገበበት ኢሜይል ወደ ${link} “${SUBJECT}” በሚል ርዕስ ይጻፉ። በGoogle ወይም በApple ከገቡ የትኛውን እንደተጠቀሙ ይግለጹ። መለያውን በ30 ቀናት ውስጥ እንሰርዛለን፣ ማረጋገጫም እንልካለን።</p>
<h2>የሚሰረዘው</h2>
<p>የመግቢያ መለያዎ፣ የሚታይ ስምዎ እና የደረጃ ሰንጠረዥ ውጤቶችዎ። የጨዋታ ክፍለ ጊዜዎችዎ ከእርስዎ ጋር ምንም ሳያገናኛቸው ይቀመጣሉ፤ ለሙዚቃ ማኅበሩ የምናቀርበው የአጫዋወት ቆጠራ ከእነሱ ይሰላል። ስለ መለያ የተያዙ የቁጥጥር መዛግብት በግላዊነት ፖሊሲያችን እንደተገለጸው ይቀመጣሉ።</p>
<h2>እንደ እንግዳ ተጫውተዋል?</h2>
<p>ገብተው የማያውቁ ከሆነ በእኛ በኩል ከስምዎ ወይም ከኢሜይልዎ ጋር የተያያዘ ነገር የለም። በመተግበሪያው ውስጥ <strong>መለያ ይሰርዙ</strong> የሚለውን ይጠቀሙ፣ ወይም መተግበሪያውን ያስወግዱ።</p>
</section>
</body>
</html>
`;
}

accountDeletion.get("/", (c) => {
  const email = c.env.PRIVACY_CONTACT_EMAIL?.trim();
  // Play needs a way to ask without the app, so the page is not served without an address.
  if (!email) throw new ApiError(503, "not_configured", "PRIVACY_CONTACT_EMAIL is not set");
  c.header("Cache-Control", `public, max-age=${CACHE_SECONDS}`);
  c.header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'");
  return c.html(accountDeletionPage(email));
});
