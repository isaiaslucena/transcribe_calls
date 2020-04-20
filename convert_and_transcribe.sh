#!/bin/bash

todaydate=$(date +%d%m%Y)
todaydateiso=$(date +"%Y-%m-%d")

tempfolder="/applications/send_to_transc/temp/"
tempcojson=${tempfolder}"companies.json"
tempfijson=${tempfolder}"files.json"
# tempfileinfo=${tempfolder}"fileinfo.json"
# temptransrep=${tempfolder}"transcription.json"
temppostsolr=${tempfolder}"postsolr.json"
# tempnoanswer=${tempfolder}"noanswer.json"

rootfolder="/applications/send_to_transc/"
notranscfiles=${rootfolder}"notranscfiles.txt"

filesfolder="/applications/audiofiles/"

companiesurl="http://127.0.0.1:83/api/get_companies"
checksolr="http://127.0.0.1:83/api/check_file"
checksolrnoaw="http://127.0.0.1:83/api/check_noanswer"
transcurl="http://127.0.0.1:8025/asr-server/rest/recognize"
savetransurl="http://127.0.0.1:83/api/save_file"

# tday=$(date +%d)
# tmon=$(date +%m)
# tmon=02
# tyea=$(date +%Y)
# tyea=2020
# for day in $(seq -f "%02g" 1 9) ; do
	 # todaydate=${day}${tmon}${tyea}
	 # todaydate=${day}012019
	 echo "${todaydate}"

	#get the companies and URLs with port
	curl -s -o "${tempcojson}" "${companiesurl}"
	arrn=$(($(jq ". | length" "${tempcojson}")-1))
	for companyarrn in $(seq 0 "${arrn}") ; do
		coid=$(jq --raw-output .[${companyarrn}].id "${tempcojson}")
		coname=$(jq --raw-output .[${companyarrn}].name "${tempcojson}")
		curl=$(jq --raw-output .[${companyarrn}].url_rec "${tempcojson}")
		curlport=$(jq --raw-output .[${companyarrn}].url_rec_port "${tempcojson}")
		cdbname=$(jq --raw-output .[${companyarrn}].db "${tempcojson}")

		if [[ "${coid}" == 1 ]] ; then
			#echo "Company:" "${coname}"
			#echo "Id:" "${coid}"

			getfilesurl="http://"${curl}":"${curlport}"/api/getfilelist?date="${todaydate}
			curl -s -o "${tempfijson}" "${getfilesurl}"
			arrn=$(($(jq ". | length" "${tempfijson}")-1))
			for filen in $(seq 0 "${arrn}") ; do
				filename=$(jq --raw-output .[${filen}] "${tempfijson}")
				filenameurl="http://"${curl}":"${curlport}"/api/getfile?date="${todaydate}"&file="${filename}

				#verify if exists on solr
				checkfileex=$(curl -s ${checksolr}"/"${coid}"/"${filename})
				if [[ "${checkfileex}" -eq 0 ]] ; then
					echo "${filename}"

					filefinalfolder=${filesfolder}${coid}"/"${todaydate}
					if [[ ! -d "${filefinalfolder}" ]] ; then
						mkdir -p "${filefinalfolder}"
					fi

					filedpath=${filefinalfolder}"/"${filename}
					if [[ ! -f "${filedpath}" ]] ; then
						curl -s -o "${filedpath}" "${filenameurl}"
					fi

					#get the file info
					getfileiurl="http://"${curl}":"${curlport}"/api/getfileinfo?filename="${filename}
					tempfileinfo=${tempfolder}${filename}"_fileinfo.json"
					curl -s -o "${tempfileinfo}" "${getfileiurl}"

					fcodigo=$(jq --raw-output .[0].Codigo "${tempfileinfo}")
					fcoment=$(jq --raw-output .[0].Coment "${tempfileinfo}")
					fporta=$(jq --raw-output .[0].Estacao "${tempfileinfo}")
					fstartrecr=$(jq --raw-output .[0].HoraIni "${tempfileinfo}")
					fstartrec=$(echo "${fstartrecr}" | sed -e 's/ /T/g')"Z"
					fendrecr=$(jq --raw-output .[0].HoraFim "${tempfileinfo}")
					fendrec=$(echo "${fendrecr}" | sed -e 's/ /T/g')"Z"
					fnfile=$(jq --raw-output .[0].NomeFile "${tempfileinfo}")
					fphone=$(jq --raw-output .[0].Telefone "${tempfileinfo}")
					ftype=$(jq --raw-output .[0].Tipo "${tempfileinfo}")
					fVolDVD=$(jq --raw-output .[0].VolumeDVD "${tempfileinfo}")
					fcodMoni=$(jq --raw-output .[0].codMonitoria "${tempfileinfo}")

					if [[ "${fcodigo}" != "null" ]] ; then
						wavfile=$(echo "${filename}" | sed -e "s/.mp3/.wav/g")
						jsonfile=$(echo "${filename}" | sed -e "s/.mp3/.json/g")

						#convert to audio rate 8k and raise volume 10dB
						echo "Converting to wav..."
						ffmpeg -loglevel quiet -i "${filedpath}" -ar 8k -filter:a "volume=10dB" -y ${tempfolder}${wavfile}
						sleep 3

						#send to transcribe
						echo "Starting transcribe..."
						transcstart=$(date +'%Y-%m-%dT%H:%M:%SZ')
						temptransrep=${tempfolder}${filename}"_transcription.json"
						curl -s -o "${temptransrep}" --header "Content-Type: audio/wav" --header "decoder.continuousMode: true" --data-binary "@"${tempfolder}${wavfile} "${transcurl}"
						transcend=$(date +'%Y-%m-%dT%H:%M:%SZ')

						resptext=$(jq --compact-output .[0].alternatives[0].text "${temptransrep}")
						respparts=$( jq --compact-output .[0].alternatives[0].words "${temptransrep}")

						if [[ "${resptext}" == "null" ]] ; then
							echo "response CPqD NULL!"
							echo "${filename}" >> "${notranscfiles}"
						else
							rm -rf ${tempfolder}${wavfile}
						fi

						temppostsolr=${tempfolder}${filename}"_postsolr.json"
						echo "Saving into Solr..."
						echo '{"id_emp":'${coid}',"id_rec":'${fcodigo}',"filename":"'${filename}'","phone":"'${fphone}'","port_rec":"'${fporta}'","type":"'${ftype}'","start_rec":"'${fstartrec}'","end_rec":"'${fendrec}'","transc_start":"'${transcstart}'","transc_end":"'${transcend}'","text_content":'${resptext}',"text_times":'${respparts}'}' > "${temppostsolr}"
						curl -s -o ${tempfolder}${filename}"_respsave.json" -H "Content-Type: application/json" -d "@"${temppostsolr} "${savetransurl}"
						sleep 1
						rm -rf "${temppostsolr}"
						rm -rf ${tempfolder}${filename}"_respsave.json"
						rm -rf "${tempfileinfo}"
						rm -rf "${temptransrep}"
					fi
					echo
				fi
			done

			echo
			# echo "Getting no answer calls..."
			getnoanswerurl="http://"${curl}":"${curlport}"/api/getnoanswer?date="${todaydateiso}
			tempnoanswer=${tempfolder}${todaydateiso}"_noanswer.json"
			curl -s -o "${tempnoanswer}" "${getnoanswerurl}"
			arrn=$(($(jq ". | length" "${tempnoanswer}")-1))
			if [[ "${arrn}" -ge 0 ]] ; then
				echo "Importing no answer calls..."
				for noansw in $(seq 0 "${arrn}") ; do
					fcodigo=$(jq --raw-output .["${noansw}"].Codigo "${tempnoanswer}")
					fcoment=$(jq --raw-output .["${noansw}"].Coment "${tempnoanswer}")
					fporta=$(jq --raw-output .["${noansw}"].Estacao "${tempnoanswer}")
					fstartrecr=$(jq --raw-output .["${noansw}"].HoraIni "${tempnoanswer}")
					fstartrec=$(echo "${fstartrecr}" | sed -e 's/ /T/g')"Z"
					fendrecr=$(jq --raw-output .["${noansw}"].HoraFim "${tempnoanswer}")
					fendrec=$(echo "${fendrecr}" | sed -e 's/ /T/g')"Z"
					fnfile=$(jq --raw-output .["${noansw}"].NomeFile "${tempnoanswer}")
					fnfl=${fporta}"_"${fstartrecr}
					fnfilen=$(echo "${fnfl}" | sed -e 's/ /_/g' -e 's/-/_/g' -e 's/:/_/g')".mp3"
					fphone=$(jq --raw-output .["${noansw}"].Telefone "${tempnoanswer}")
					ftype="N"
					fVolDVD=$(jq --raw-output .["${noansw}"].VolumeDVD "${tempnoanswer}")
					fcodMoni=$(jq --raw-output .["${noansw}"].codMonitoria "${tempnoanswer}")

					#verify if exists on solr
					checkfileex=$(curl -s ${checksolrnoaw}"/"${coid}"/"${fcodigo})
					if [[ "${checkfileex}" -eq 0 ]] ; then
						echo "${fnfilen}"
						echo "ID" "${fcodigo}" "saving into Solr..."
						echo '{"id_emp":'${coid}',"id_rec":'${fcodigo}',"filename":"'${fnfilen}'","phone":"'${fphone}'","port_rec":"'${fporta}'","type":"'${ftype}'","start_rec":"'${fstartrec}'","end_rec":"'${fendrec}'","transc_start":"'${fstartrec}'","transc_end":"'${fstartrec}'","text_content":["no answer"],"text_times":"[\"no answer\"]"}' > "${temppostsolr}"
						curl -s -o "${tempfolder}""respsave.json" -H "Content-Type: application/json" -d "@"${temppostsolr} "${savetransurl}"
						# jq . ${tempfolder}${fnfilen}"_respsave_noanswer.json"
						sleep 1
						rm -rf "${tempfolder}""respsave.json"
						rm -rf "${tempnoanswer}"
						echo
					fi
				done
				echo "Done!"
				echo
			fi
		fi
	done
# done
