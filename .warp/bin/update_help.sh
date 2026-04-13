#!/bin/bash

function update_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp update [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " -f, --force        $(warp_message 'force update without confirmation')"
    warp_message_info   " self, --self       $(warp_message 'apply payload from current ./warp without remote download')"
    warp_message_info   " --images           $(warp_message 'update images from hub registry docker')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " warp update downloads dist/version.md, dist/sha256sum.md and dist/warp from"
    warp_message " https://github.com/magtools/phoenix-launch-silo and validates SHA-256 before replacing ./warp."
    warp_message " warp update self / --self does not download remote artifacts: it applies the payload embedded in"
    warp_message " the current local ./warp and is the correct command when the executable is newer than .warp."
    warp_message " if Warp warns that the binary and installed framework are out of sync, run ./warp update --self."
    warp_message " if a global PATH warp is outdated, Warp now prefers installing a delegating wrapper from"
    warp_message " .warp/setup/bin/warp-wrapper.sh instead of copying the project binary into system paths."
    warp_message " warp update --images only pulls Docker images and does not update the Warp framework."

    warp_message ""

}

function update_help()
{
    warp_message_info   " update             $(warp_message 'update warp framework')"

}
