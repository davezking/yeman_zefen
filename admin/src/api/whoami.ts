import { useQuery } from "@tanstack/react-query";
import { z } from "zod";
import { apiFetch } from "./client";

const whoamiSchema = z.object({
  admin: z.object({
    email: z.string(),
    role: z.enum(["admin", "editor"]),
  }),
});

export type Whoami = z.infer<typeof whoamiSchema>["admin"];

export function useWhoami() {
  return useQuery({
    queryKey: ["whoami"],
    queryFn: async () => (await apiFetch("/admin/whoami", whoamiSchema)).admin,
    retry: false,
  });
}
