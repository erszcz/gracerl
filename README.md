# Gracerl - the ugly kid of Graphite and Tracerl

Usage:

    ./start.sh monitored@node

`monitored@node` must be compiled with DTrace / SystemTap,
similarly as is the case with `tracerl`.

There might be some leftover details specific to my environment
in the code (though I hope not).

## ToDo

- [ ] no message queue size monitored, so no convenient visibility of outliers,
  this needs tweaking the probes served to DTrace / SystemTap

- [ ] no OTP process hierarchy mirrored in metric names,
  so there's only a flat namespace of processes visible in Graphite
  dashborad; this might be inspired by how OTP appmon build this hierarchy
  for displaying using OTP webtool

- [ ] maybe the metric format should be: `nodes.node.otp-tree-and-pid.metric`
  instead of `nodes.metric.otp-tree-and-pid.`;
  I'm more for the pid-then-metric than the current format
