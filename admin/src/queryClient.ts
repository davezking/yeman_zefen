import { notifications } from "@mantine/notifications";
import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";
import { ApiError } from "./api/client";

export function errorTitle(error: Error): string {
  if (!(error instanceof ApiError)) return "Something went wrong";
  if (error.status === 0) return "Can't reach the API";
  if (error.status === 401) return "Sign-in required";
  if (error.status === 403) return "Not allowed";
  return "Request failed";
}

export function errorMessage(error: Error): string {
  if (error instanceof ApiError && error.requestId) return `${error.message} (request ${error.requestId})`;
  return error.message;
}

// One place turns failed queries and mutations into readable notifications, so
// pages never render a blank screen on an API error.
function notifyError(error: Error) {
  notifications.show({ color: "red", title: errorTitle(error), message: errorMessage(error) });
}

// A mutation with `meta: { silent: true }` reports its own errors, in place, next to what the admin was doing.
export const queryClient = new QueryClient({
  // A query with `meta: { silent: true }` shows its own error too.
  queryCache: new QueryCache({ onError: (error, query) => { if (!query.meta?.silent) notifyError(error); } }),
  mutationCache: new MutationCache({
    onError: (error, _variables, _onMutateResult, mutation) => {
      if (!mutation.meta?.silent) notifyError(error);
    },
  }),
  defaultOptions: { queries: { staleTime: 30_000 } },
});
