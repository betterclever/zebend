#!/bin/zsh
# crashwhy.sh: the reason Apple's GPU compiler gave in its newest crash report.
f=$(ls ~/Library/Logs/DiagnosticReports/MTLCompilerService-*.ips | sort | tail -1); echo $f
python3 -c "
import json,sys
t=open(sys.argv[1]).read().split('\n',1)[1]; j=json.loads(t)
print('\n'.join(j['termination'].get('reasons',['?'])[:${1:-14}]))
" $f
