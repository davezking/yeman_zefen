/** Public URL of an object in the `yz-clips` bucket, served at CDN_BASE_URL. The one place that joins the two. */
export const cdnUrl = (cdnBase: string, key: string) => `${cdnBase.replace(/\/+$/, "")}/${key}`;
