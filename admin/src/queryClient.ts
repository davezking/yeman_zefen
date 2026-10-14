import { notifications } from "@mantine/notifications";
import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";
import { ApiError } from "./api/client";

// One place turns failed queries and mutations into readable notifications, so
// pages never render a blank screen on an API error.
function notifyError(error: Error) {
  notifications.show({
    color: "red",
    title: error instanceof ApiError && error.status === 401 ? "Sign-in required" : "Request failed",
    message: error.message,
  });
}

export const queryClient = new QueryClient({
  queryCache: new QueryCache({ onError: notifyError }),
  mutationCache: new MutationCache({ onError: notifyError }),
  defaultOptions: { queries: { staleTime: 30_000 } },
});
