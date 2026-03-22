#!/bin/bash +x

echo ""
warp_message_info "Configuring Search Service"

while : ; do
    respuesta_es=$( warp_question_ask_default "Do you want to add a search service? $(warp_message_info [Y/n]) " "Y" )
    if [ "$respuesta_es" = "Y" ] || [ "$respuesta_es" = "y" ] || [ "$respuesta_es" = "N" ] || [ "$respuesta_es" = "n" ] ; then
        break
    else
        warp_message_warn "wrong answer, you must select between two options: $(warp_message_info [Y/n]) "
    fi
done

if [ "$respuesta_es" = "Y" ] || [ "$respuesta_es" = "y" ]
then
    search_engine=$(warp_service_version_engine_default search)
    search_engines_allowed=$(warp_app_context_engines_csv search)
    search_compat_note=$(warp_app_context_search_note 2>/dev/null || true)

    if [ -n "$search_compat_note" ]; then
        warp_message_info2 "$search_compat_note"
    fi

    if printf '%s' "$search_engines_allowed" | grep -q '|'; then
        if [ "$WARP_APP_FRAMEWORK" = "magento" ] && [ "$WARP_APP_COMPAT_PROFILE" != "general" ]; then
            warp_message_info2 "Additional search engines are shown because Warp detected Magento compatibility profile: $(warp_message_info "$WARP_APP_COMPAT_PROFILE")"
        fi
        warp_app_context_show_engine_options search
        while : ; do
            _selected_engine=$(warp_question_ask_default "Choose the search engine: $(warp_message_info [$search_engine]) $(warp_message '[ '"$search_engines_allowed"' ]') " "$search_engine")
            case "$_selected_engine" in
                opensearch|elasticsearch)
                    if warp_app_context_engine_class search "$_selected_engine" >/dev/null 2>&1; then
                        search_engine="$_selected_engine"
                        break
                    fi
                    ;;
            esac
            warp_message_warn "wrong engine, choose one of: $(warp_message_info "$search_engines_allowed")"
        done
    fi

    search_image_repo=$(warp_service_version_image_repo search "$search_engine")
    search_version_default=$(warp_service_version_tag_default search "$search_engine")
    search_tags_suggested=$(warp_service_version_tags_csv search "$search_engine" suggested)
    search_tags_legacy=$(warp_service_version_tags_csv search "$search_engine" legacy)

    warp_message_info2 "Selected search engine: $(warp_message_info "$search_engine") [$(warp_app_context_engine_class search "$search_engine")]"
    if [ "$search_engine" = "elasticsearch" ]; then
        warp_message_info2 "You can check the available versions of ${search_engine} here $(warp_message_info '[ https://www.docker.elastic.co/r/elasticsearch/elasticsearch ]')"
    else
        warp_message_info2 "You can check the available versions of ${search_engine} here $(warp_message_info '[ https://hub.docker.com/r/opensearchproject/opensearch/tags/ ]')"
    fi
    [ -n "$search_tags_suggested" ] && warp_message_info2 "Suggested ${search_engine} tags: $(warp_message_info "$search_tags_suggested")"
    [ -n "$search_tags_legacy" ] && warp_message_info2 "Legacy/manual ${search_engine} tags: $(warp_message_info "$search_tags_legacy")"

    elasticsearch_version=$( warp_service_version_prompt_tag search "$search_engine" "Choose a version of ${search_engine}: $(warp_message_info [$search_version_default]) " "$search_version_default" )

    warp_message_info2 "Selected search engine/version: ${search_engine}:${elasticsearch_version}, in the internal ports 9200, 9300 $(warp_message_bold 'elasticsearch:9200, elasticsearch:9300')"
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
    echo "SEARCH_ENGINE=$search_engine" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_VERSION=$elasticsearch_version" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_IMAGE=${search_image_repo}:${elasticsearch_version}" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_SCHEME=http" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_HOST=elasticsearch" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "SEARCH_PORT=9200" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo ""  >> $ENVIRONMENTVARIABLESFILESAMPLE

fi; 
