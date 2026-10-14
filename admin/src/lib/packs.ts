export const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export const megabytes = (bytes: number) => `${(bytes / 1_048_576).toFixed(1)} MB`;
