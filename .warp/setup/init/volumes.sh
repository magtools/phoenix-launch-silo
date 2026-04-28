warp_compose_sample_append_dev "$PROJECTPATH/.warp/setup/init/tpl/appdata.yml" || exit 1

cp -R $PROJECTPATH/.warp/setup/init/config/appdata $PROJECTPATH/.warp/docker/config/appdata
cp -R $PROJECTPATH/.warp/setup/init/config/bash $PROJECTPATH/.warp/docker/config/bash
cp -R $PROJECTPATH/.warp/setup/init/config/etc $PROJECTPATH/.warp/docker/config/etc
mkdir -p $PROJECTPATH/.warp/docker/config/agents
[ ! -f $PROJECTPATH/.warp/docker/config/agents/config.ini ] && cp $PROJECTPATH/.warp/setup/init/config/agents/config.ini $PROJECTPATH/.warp/docker/config/agents/config.ini
mkdir -p $PROJECTPATH/.warp/docker/config/lint
cp $PROJECTPATH/.warp/setup/init/config/lint/TestPR.xml $PROJECTPATH/.warp/docker/config/lint/TestPR.xml
