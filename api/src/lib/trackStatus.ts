import { OUT_OF_CATALOG } from "../db/schema";

/** Rejected or retired: out of the catalog, so nothing about the track is left to review. */
export function isOutOfCatalog(status: string): boolean {
  return (OUT_OF_CATALOG as readonly string[]).includes(status);
}
