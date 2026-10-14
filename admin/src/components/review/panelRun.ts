import { useState } from "react";
import { ApiError } from "../../api/client";

/**
 * Runs one action of a resolution panel and keeps its error where the admin is looking, next to the buttons.
 * `run` resolves to true when the action went through.
 */
export function usePanelRun() {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function run(action: () => Promise<unknown>): Promise<boolean> {
    setError(null);
    setBusy(true);
    try {
      await action();
      return true;
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Request failed");
      return false;
    } finally {
      setBusy(false);
    }
  }

  return { error, busy, run };
}
