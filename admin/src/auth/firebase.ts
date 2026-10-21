// Google sign-in through Firebase Auth, for VITE_ADMIN_LOGIN=firebase. Loaded with a dynamic import, so a
// site that signs in through Cloudflare Access never downloads the Firebase SDK.
import { initializeApp } from "firebase/app";
import { GoogleAuthProvider, getAuth, onAuthStateChanged, signInWithPopup, signOut as firebaseSignOut, type Auth, type User } from "firebase/auth";

let auth: Auth | null = null;

function firebaseAuth(): Auth {
  if (!auth) {
    // The Firebase web app's config (Project settings › Your apps). These are public identifiers, not secrets.
    const app = initializeApp({
      apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
      authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
      projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
      appId: import.meta.env.VITE_FIREBASE_APP_ID,
    });
    auth = getAuth(app);
  }
  return auth;
}

/** The signed-in admin's ID token (refreshed by Firebase when it is close to expiring), or null when signed out. */
export async function idToken(): Promise<string | null> {
  const user = firebaseAuth().currentUser;
  return user ? user.getIdToken() : null;
}

export async function signInWithGoogle(): Promise<void> {
  const provider = new GoogleAuthProvider();
  // Always ask which account, so someone signed in to the wrong Google account can pick the right one.
  provider.setCustomParameters({ prompt: "select_account" });
  await signInWithPopup(firebaseAuth(), provider);
}

export const signOut = (): Promise<void> => firebaseSignOut(firebaseAuth());

/** Calls `onChange` with the current user now and on every sign-in or sign-out. Returns the unsubscribe. */
export const watchUser = (onChange: (user: User | null) => void): (() => void) => onAuthStateChanged(firebaseAuth(), onChange);
