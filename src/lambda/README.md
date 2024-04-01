### test

TOKEN=`cat src/token.txt` && curl -X POST https://zl71d58431.execute-api.us-west-2.amazonaws.com/dev/deadman -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json'