// Vite's `?raw` suffix imports a file as a string (tests use it to read docs/).
// No imports here: a wildcard module declaration must be in a global script file.
declare module "*?raw" {
  const content: string;
  export default content;
}
