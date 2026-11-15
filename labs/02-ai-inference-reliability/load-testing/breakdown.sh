#!/bin/sh
# usage: breakdown.sh <concurrency>   (run inside the bench pod; needs curl, jq, date)
C=${1:-1}; URL=http://ollama:11434/api/generate
BODY='{"model":"qwen2.5:0.5b","prompt":"Explain Kubernetes taints and tolerations in 5 bullet points.","stream":false,"options":{"num_predict":128}}'
echo "req,wall_s,server_total_s,queue_s,prefill_s,decode_s,tok_per_s"
for i in $(seq 1 $C); do
  ( s=$(date +%s%N)
    r=$(curl -s $URL -d "$BODY")
    e=$(date +%s%N)
    echo "$r" | jq -r --arg i $i --arg w $(( (e-s)/1000000 )) '
      ($w|tonumber/1000) as $wall |
      [$i, $wall, (.total_duration/1e9),
       ($wall - .total_duration/1e9),          # queue + network
       (.prompt_eval_duration/1e9),            # prefill
       (.eval_duration/1e9),                   # decode
       (.eval_count/(.eval_duration/1e9))] | @csv' ) &
done; wait
