#!/bin/sh
erl -setcookie ejabberd -sname gracerl -pa ebin deps/*/ebin -s gracerl \
    -gracerl carbon_host \"10.100.0.70\" \
    -gracerl carbon_port 2003 \
    -gracerl node $@
