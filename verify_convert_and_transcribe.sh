#!/bin/bash

now=$(date '+%F %T')

pid=$(pidof -x "convert_and_transcribe.sh")
if [[ -z ${pid} ]] ; then
	echo "${now}" "- convert_and_transcribe.sh is not running!"
	/applications/send_to_transc/convert_and_transcribe.sh >> /applications/send_to_transc/convert_and_transcribe.log &
else
	echo "${now}" "- convert_and_transcribe.sh is running!"
fi
