#!/bin/bash +x

echo ""
warp_message_info "Configuring ElasticSearch Service"

while : ; do
    respuesta_es=$( warp_question_ask_default "Do You want to add an elasticsearch service? $(warp_message_info [Y/n]) " "Y" )
    if [ "$respuesta_es" = "Y" ] || [ "$respuesta_es" = "y" ] || [ "$respuesta_es" = "N" ] || [ "$respuesta_es" = "n" ] ; then
        break
    else
        warp_message_warn "wrong answer, you must select between two options: $(warp_message_info [Y/n]) "
    fi
done

if [ "$respuesta_es" = "Y" ] || [ "$respuesta_es" = "y" ]
then
    warp_message_info2 "You can check the available versions of elasticsearch here $(warp_message_info '[ https://hub.docker.com/r/summasolutions/opensearch/tags/ ]')"
    
    while : ; do
    if [ $(uname -m) == 'arm64' ] ; then
        elasticsearch_version=$( warp_question_ask_default "Choose a version of elasticsearch: $(warp_message_info [7.10.1_arm]) " "7.10.1_arm" )
    else 
        elasticsearch_version=$( warp_question_ask_default "Choose a version of elasticsearch: $(warp_message_info [2.12.0]) " "2.12.0" )
    fi
        case $elasticsearch_version in
        '2.12.0'|'1.7.6')
            break;
        ;;
        *)
            warp_message_info2 "Selected: $elasticsearch_version, the available versions are: 2.12.0"
        ;;
        esac        
    done
    warp_message_info2 "Selected version of elasticsearch: $elasticsearch_version, in the internal ports 9200, 9300 $(warp_message_bold 'elasticsearch:9200, elasticsearch:9300')"
    elasticsearch_memory=$( warp_question_ask_default "Set memory limit of elasticsearch: $(warp_message_info [1g]) " "1g" )
    warp_message_info2 "Selected memory limit of elasticsearch: $elasticsearch_memory"

    cat $PROJECTPATH/.warp/setup/elasticsearch/tpl/elasticsearch.yml >> $DOCKERCOMPOSEFILESAMPLE

    echo ""  >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "# Elasticsearch" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "ES_VERSION=$elasticsearch_version" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "ES_MEMORY=$elasticsearch_memory" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "ES_PASSWORD=XmsES_MEMORY++99" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "# Canonical SEARCH Configuration" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_MODE=local" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_ENGINE=opensearch" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_SCHEME=http" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_HOST=elasticsearch" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_PORT=9200" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo ""  >> $ENVIRONMENTVARIABLESFILESAMPLE

fi; 
