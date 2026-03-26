#!/bin/bash

function search_help_usage()
{
    elasticsearch_help_usage
}

function search_help()
{
    warp_message_info   " search             $(warp_message 'utility for search service operations (elasticsearch/opensearch)')"
    warp_message_info   " elasticsearch      $(warp_message 'alias of search (legacy compatibility)')"
    warp_message_info   " opensearch         $(warp_message 'alias of search (engine compatibility)')"
}
