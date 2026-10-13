// A stand-in for GitHub's API in tests. Every test starts with one that records dispatches and answers 204,
// so nothing here ever reaches the network; a test that cares about errors replaces the answer.
import { beforeEach } from "vitest";
import { __setGithubFetch } from "../src/lib/github";

export type GithubCall = {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: { ref: string; inputs: Record<string, string> };
};

export const githubCalls: GithubCall[] = [];
const noContent = () => new Response(null, { status: 204 });
let answer: (call: GithubCall) => Response | Promise<Response> = noContent;

/** Make GitHub answer (or fail) the next dispatches. Reset before each test. */
export function githubAnswers(fn: (call: GithubCall) => Response | Promise<Response>): void {
  answer = fn;
}

export function installGithubFake(): void {
  beforeEach(() => {
    githubCalls.length = 0;
    answer = noContent;
    __setGithubFetch(async (input, init) => {
      const call: GithubCall = {
        url: String(input),
        method: init?.method ?? "GET",
        headers: Object.fromEntries(new Headers(init?.headers).entries()),
        body: JSON.parse(String(init?.body ?? "{}")),
      };
      githubCalls.push(call);
      return answer(call);
    });
  });
}
