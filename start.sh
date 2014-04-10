#!/bin/sh
erl -setcookie ejabberd -sname gracerl -pa ebin deps/*/ebin -s gracerl -gracerl node $@
