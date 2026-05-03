#!/bin/bash +x

while : ; do
    private_registry_mode=$( warp_question_ask_default "Do you want to configure this project with a private Docker Registry? $(warp_message_info [y/N]) " "N" )

    if [ "$private_registry_mode" = "Y" ] || [ "$private_registry_mode" = "y" ] || [ "$private_registry_mode" = "N" ] || [ "$private_registry_mode" = "n" ] ; then
        break
    else
        warp_message_warn "wrong answer, you must select between two options: $(warp_message_info [Y/n]) "
    fi
done

if [ "$private_registry_mode" = "Y" ] || [ "$private_registry_mode" = "y" ] ; then
    while : ; do
        namespace_name=$( warp_question_ask "Namespace name, use lowercase letters or numbers with a maximum of 12 characters and optional hyphen, for example 'starfleet': " )

        if warp_env_is_valid_image_name_component "$namespace_name"; then
            warp_message_info2 "The namespace name: $(warp_message_bold $namespace_name)"
            break
        else
            warp_message_warn "incorrect value, use only lowercase letters or numbers, optionally separated by one hyphen\n"
        fi;
    done

    while : ; do
        project_name=$( warp_question_ask "Project Name, use lowercase letters or numbers with a maximum of 12 characters and optional hyphen, for example 'warp-engine': " )

        if warp_env_is_valid_image_name_component "$project_name"; then
            warp_message_info2 "The project name is: $(warp_message_bold $project_name)"
            break
        else
            warp_message_warn "incorrect value, use only lowercase letters or numbers, optionally separated by one hyphen\n"
        fi;
    done

    while : ; do
        docker_private_registry=$( warp_question_ask "Docker Private Registy URL: " )

        if warp_env_is_valid_private_registry "$docker_private_registry"; then
            warp_message_info2 "The docker private registry url is: $(warp_message_bold $docker_private_registry)"
            break
        else
            warp_message_warn "incorrect registry value, use host[:port][/namespace] without http:// or https:// and without trailing slash\n"
        fi;
    done

    # Docker Compose Project Name:
    COMPOSE_PROJECT_NAME=$namespace_name\-$project_name
else
    # If we don't set up docker registry we will add a random project name in order to isolate warp environment projects:
    COMPOSE_PROJECT_NAME=$(warp_env_random_name 7)
fi

while : ; do
    framework=$( warp_question_ask_default "Select the main framework for this project. Possible values are $(warp_message_info [m1/m2/oro/php]): " "m2" )

    case $framework in
        'm1')
            break
        ;;
        'm2')
            break
        ;;
        'oro')
            break
        ;;
        'php')
            break
        ;;
        *)
            warp_message_info2 "Selected: $framework, the available options are m1, m2, oro, php"
        ;;
    esac
done



echo "# Project configurations" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "NAMESPACE=${namespace_name}" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "PROJECT=${project_name}" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "DOCKER_PRIVATE_REGISTRY=${docker_private_registry}" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "FRAMEWORK=${framework}" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE

printf "# Docker Compose Project Name:\n" >> $ENVIRONMENTVARIABLESFILESAMPLE
printf "COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME\n\n" >> $ENVIRONMENTVARIABLESFILESAMPLE

echo "# Docker configurations" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "COMPOSE_HTTP_TIMEOUT=$DOCKER_COMPOSE_HTTP_TIMEOUT" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "APPDATA_IMAGE_REPO=magtools" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "APPDATA_VERSION=bookworm" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE

echo "# VERSION Configuration" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "WARP_VERSION=$WARP_VERSION" >> $ENVIRONMENTVARIABLESFILESAMPLE
echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE
