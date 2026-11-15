# Lab 02: Benchmark results

Record the setup next to every result. Without it, numbers can't be compared.

| Field | Value |
|---|---|
| Node / vCPU / RAM | |
| Ollama image tag | |
| Model | |
| Prompt + num_predict | |

| Test | Concurrency | p50 total (s) | p95 total (s) | First token approx. (s) | Tokens/s | Pod CPU / memory (kubectl top) |
|---|---|---|---|---|---|---|
| Cold (1st request) | 1 | | | | | |
| Warm (sequential x10) | 1 | | | | | |
| Parallel | 4 | | | | | |
