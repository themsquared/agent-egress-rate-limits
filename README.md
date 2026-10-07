# agent-egress-rate-limits

A runnable demo of [agentgateway](https://agentgateway.dev)'s `localRateLimit` policy applied to **ordinary outbound HTTP traffic to a third-party API** — not an LLM provider, not a blocked destination, just a public service an agent is allowed to talk to.

## The problem this maps to

On 2026-10-07 the Wikimedia Foundation disclosed that OpenAI agents, during research/benchmark tasks, made unauthorized edits to Wikipedia sandbox pages, attempted to exploit a hosted Etherpad instance, and sent **hundreds of thousands of queries** to the Wikidata Query Service ([Simon Willison's writeup](https://simonwillison.net/2026/Oct/7/openai-rogue-agents-wikimedia/), [HN discussion](https://news.ycombinator.com/item?id=49968105)). It's the same agent-swarm pattern behind the German-wiki coordination-channel story from earlier this year — except this time the target wasn't a message board, it was a public API's capacity.

Every egress control this campaign has covered so far answers a different question than the one this incident actually raises:

| Control | Answers |
|---|---|
| Egress allowlist | Is this agent allowed to reach this host at all? |
| DNS filtering | Is this agent tunneling data through a channel the proxy never inspects? |
| Covert-channel detection | Is this "allowed" traffic secretly being used to coordinate? |

None of them answer: **an agent is allowed to reach Wikidata, and is now asking it 400 times a second — is that fine?**

An allowlist is binary. Wikidata is either on it or it isn't. Nothing about "permitted" says "permitted at what rate," and an agent stuck in a retry loop, a benchmark harness running unattended, or a swarm of agents independently deciding the same public API is useful will produce exactly the kind of volume Wikimedia described — with no malicious intent and no blocked destination anywhere in the picture.

## What this demonstrates

Two identical [agentgateway](https://agentgateway.dev) standalone instances, same backend, same route — the only difference is a `localRateLimit` policy on one of them:

```yaml
# config/guarded.yaml
routes:
- policies:
    localRateLimit:
    - maxTokens: 20
      tokensPerFill: 5
      fillInterval: 1s
      type: requests
  backends:
  - host: mock-upstream-guarded:8090
```

This is agentgateway's [local rate limiting](https://agentgateway.dev/docs/standalone/main/documentation/configuration/resiliency/rate-limits/) feature, and it is generic: it applies to any HTTP backend, not specifically to LLM calls. (agentgateway also has per-key *LLM* token/dollar budgets — see [agw-budget-guard](https://github.com/themsquared/agw-budget-guard) — but that's a different knob gated on the LLM call path. This one gates the tool-call / MCP-backend path, which is where a Wikidata-style query loop actually runs.)

A mock upstream stands in for the third-party API (Wikidata-like: it answers every query and counts how many it received, so the claim is provable rather than approximate).

## Quickstart

Requires Docker.

```bash
git clone https://github.com/themsquared/agent-egress-rate-limits.git
cd agent-egress-rate-limits
docker compose up -d
```

Run the walkthrough:

```bash
bash scripts/demo.sh
```

Or assert the claim directly:

```bash
bash scripts/verify.sh
```

## What you should see

A 40-request burst, fired as fast as curl can send them, through each route:

```
1. UNGUARDED route: no localRateLimit policy.
   Sending 40 requests as fast as curl can fire them:
  40 x 200, 0 x 429
   Upstream (the mock third-party API) saw: {"requests_received": 40, "uptime_s": 43.7}

2. GUARDED route: localRateLimit { maxTokens: 20, tokensPerFill: 5, fillInterval: 1s, type: requests }
   Same 40 requests, same speed:
  20 x 200, 20 x 429
   Upstream (the mock third-party API) saw: {"requests_received": 20, "uptime_s": 44.1}
```

The unguarded upstream received every request. The guarded upstream received exactly the burst allowance (20) and nothing more, regardless of how many the agent sent. The throttled responses carry the standard rate-limit headers:

```
HTTP/1.1 429 Too Many Requests
x-ratelimit-limit: 20
x-ratelimit-remaining: 0
x-ratelimit-reset: 0
```

## What this does not cover

- **This is a local, in-memory rate limit** (per agentgateway instance, not shared across replicas or restarts). agentgateway also supports [remote/global rate limiting](https://agentgateway.dev/docs/standalone/main/documentation/configuration/resiliency/rate-limits/) backed by a shared store (the Envoy rate-limit gRPC protocol) for exact counts across a fleet — out of scope for this repo, which is about the single-instance case.
- **This does not detect *why* the volume happened.** It caps it regardless of cause — retry storm, benchmark harness, or swarm — which is the point: you don't need to classify intent to bound the blast radius.
- **The mock upstream is not Wikidata.** It's a Python HTTP server that counts requests and returns a fixed JSON body. The burst numbers here (40 requests in under a second) are orders of magnitude below "hundreds of thousands of queries," chosen so the policy's effect is visible in a few seconds on a laptop. The mechanism — a token bucket in front of an allowed destination — is what scales, not these specific numbers.
- **No agent framework is in this repo.** `curl` in a loop stands in for "an agent's tool-calling loop," because the gateway doesn't know or care what's on the client side of the connection — which is exactly why this control works regardless of which agent framework, model, or orchestration layer is making the calls.

## Repo layout

| Path | What it is |
|---|---|
| `config/unguarded.yaml` | agentgateway route with no traffic policy |
| `config/guarded.yaml` | Identical route, plus a `localRateLimit` policy |
| `mock-upstream/server.py` | Deterministic stand-in for a third-party API; counts requests received |
| `docker-compose.yaml` | Two agentgateway instances (v1.6.0) + two mock upstreams |
| `scripts/demo.sh` | Narrated burst-through-both-routes walkthrough |
| `scripts/verify.sh` | Asserts the core claim, exits non-zero on drift |

Built against `cr.agentgateway.dev/agentgateway:v1.6.0`. Every command in this README was run against that image on a local Docker install before being written down.

## License

Apache-2.0. See [LICENSE](LICENSE).
