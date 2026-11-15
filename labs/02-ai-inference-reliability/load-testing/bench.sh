#!/bin/sh
# usage: bench.sh <model> <requests>
M=${1:-qwen2.5:0.5b}; N=${2:-10}
URL=http://ollama.ai-lab.svc.cluster.local:11434/api/generate
P='Write 3 bullet points on Linux cgroups.'
echo "run,total_s,first_token_s,tokens,tok_per_s"
i=1
while [ $i -le $N ]; do
  curl -s $URL -d "{\"model\":\"$M\",\"prompt\":\"$P\",\"stream\":false,\"options\":{\"num_predict\":128}}" |
  jq -r --arg i $i '[$i,
    (.total_duration/1e9),
    ((.load_duration+.prompt_eval_duration)/1e9),
    .eval_count,
    (.eval_count/(.eval_duration/1e9))] | @csv'
  i=$((i+1))
done
