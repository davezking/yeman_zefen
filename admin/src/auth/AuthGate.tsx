import { Alert, Button, Center, Loader, Paper, Stack, Text, Title } from "@mantine/core";
import { useEffect, useState, type ReactNode } from "react";
import { queryClient } from "../queryClient";
import { adminLogin } from "./login";

/**
 * Shows the site only to a signed-in admin when VITE_ADMIN_LOGIN=firebase. With Cloudflare Access (the default)
 * Access has already signed the admin in before the page loads, so there is nothing to do here.
 */
export function AuthGate({ children }: { children: ReactNode }) {
  return adminLogin() === "firebase" ? <FirebaseGate>{children}</FirebaseGate> : <>{children}</>;
}

function FirebaseGate({ children }: { children: ReactNode }) {
  // undefined while Firebase restores a saved sign-in, null when signed out.
  const [signedIn, setSignedIn] = useState<boolean | undefined>(undefined);

  useEffect(() => {
    let unsubscribe: (() => void) | undefined;
    let cancelled = false;
    void import("./firebase").then((m) => {
      if (cancelled) return;
      unsubscribe = m.watchUser((user) => {
        // Another account's data must not stay on screen after a sign-out or an account switch.
        queryClient.clear();
        setSignedIn(user !== null);
      });
    });
    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, []);

  if (signedIn === undefined) {
    return (
      <Center h="100vh">
        <Loader />
      </Center>
    );
  }
  return signedIn ? <>{children}</> : <SignIn />;
}

function SignIn() {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const signIn = async () => {
    setBusy(true);
    setError(null);
    try {
      await (await import("./firebase")).signInWithGoogle();
    } catch (err) {
      const code = (err as { code?: string }).code;
      // Closing the Google window is not an error worth showing.
      if (code !== "auth/popup-closed-by-user" && code !== "auth/cancelled-popup-request") {
        setError(code === "auth/unauthorized-domain"
          ? "This address is not allowed to sign in. Add it under Firebase › Authentication › Settings › Authorized domains."
          : "Sign-in did not work. Try again.");
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <Center h="100vh" p="md">
      <Paper withBorder p="xl" radius="md" maw={380} w="100%">
        <Stack>
          <Title order={3}>Yeman Zefen admin</Title>
          <Text size="sm" c="dimmed">Sign in with the Google account an admin has added.</Text>
          {error && <Alert color="red">{error}</Alert>}
          <Button onClick={() => void signIn()} loading={busy}>Sign in with Google</Button>
        </Stack>
      </Paper>
    </Center>
  );
}

/** Signs out (VITE_ADMIN_LOGIN=firebase); AuthGate then shows the sign-in screen. */
export async function signOutAdmin(): Promise<void> {
  await (await import("./firebase")).signOut();
}
