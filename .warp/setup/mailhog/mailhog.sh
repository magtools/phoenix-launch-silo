#!/bin/bash +x

warp_message ""
warp_message_info "Configuring Mail service"

while : ; do
    respuesta_mailhog=$( warp_question_ask_default "Do you want to add the Mail service? $(warp_message_info [Y/n]) " "Y" )

    if [ "$respuesta_mailhog" = "Y" ] || [ "$respuesta_mailhog" = "y" ] || [ "$respuesta_mailhog" = "N" ] || [ "$respuesta_mailhog" = "n" ] ; then
        break
    else
        warp_message_warn "wrong answer, you must select between two options: $(warp_message_info [Y/n]) "
    fi
done

if [ "$respuesta_mailhog" = "Y" ] || [ "$respuesta_mailhog" = "y" ]
then

    while : ; do
        mailhog_binded_port=$( warp_question_ask_default "Plase select the port of your machine (host) to Web interface to view the messages: $(warp_message_info [$MAIL_BINDED_PORT_DEFAULT]) " "$MAIL_BINDED_PORT_DEFAULT" )

        if ! warp_net_port_in_use $mailhog_binded_port ; then
            warp_message_info2 "the selected port is: $mailhog_binded_port, Web interface to view the messages: $(warp_message_bold 'http://127.0.0.1:'$mailhog_binded_port)"
            break
        else
            warp_message_warn "The port $mailhog_binded_port is busy, choose another one\n"
        fi;
    done

    cat $PROJECTPATH/.warp/setup/mailhog/tpl/mailhog.yml >> $DOCKERCOMPOSEFILESAMPLE

    echo "# Config Mail" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "MAIL_ENGINE=$MAIL_ENGINE_DEFAULT" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "MAIL_VERSION=$MAIL_VERSION_DEFAULT" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "MAIL_BINDED_PORT=$mailhog_binded_port"  >> $ENVIRONMENTVARIABLESFILESAMPLE

    echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE

    warp_env_file_sync_mail_binded_port "$ENVIRONMENTVARIABLESFILESAMPLE" "$mailhog_binded_port" || exit 1
    warp_mail_ensure_auth_files "$ENVIRONMENTVARIABLESFILESAMPLE" || exit 1

    warp_message ""
fi; 
