#!/bin/bash -x

echo "Do you really want to delete all recordings? (Y/n)"
read conf

if [[ "${conf}" == "Y" ]]; then
	curl http://callmonitor.tear.inf.br:8983/solr/recordings/update --data '<delete><query>*:*</query></delete>' -H 'Content-type:text/xml; charset=utf-8'
	curl http://callmonitor.tear.inf.br:8983/solr/recordings/update --data '<commit/>' -H 'Content-type:text/xml; charset=utf-8'
else
	exit
fi
