+++
title = "Latency of Reliable Streams"
date = 2020-04-10
description = "An investigation of game network protocols, part 2"
draft = false
aliases = []

[extra]
rss_include = true
+++


This is the second article in a series in which I investigate what the ideal
network protocol for games looks like. You can find the last article
[here](https://paytonturnage.com/writing/ideal-game-network-protocol/).

Unreliable sequenced delivery is the workhorse of most online multiplayer game
netcode, but with the diversity of netcode and game loops in the world I think
trying to define, measure, and optimize a general solution to this is a fool’s
errand. There are a few parameters to improve this delivery method for packet
loss, such as pacing of packet transmission and backpressure on the netcode
based on bandwidth estimations. Exposing these parameters to users is
sufficient.

I was not excited to reach this boring conclusion, but fortunately there remains
an interesting area to measure and benchmark: low latency reliable ordered
streams of periodic payloads. These are employed by a few genres of discrete
step games, games using state synchronization [served by distributed
systems](https://improbable.io/blog/kcp-a-new-low-latency-secure-network-stack),
and many games that really ought to be using something else.


### Contenders

I chose three protocols to measure: TCP as a reference,
[ENet](https://github.com/lsalzman/enet) as the status quo, and
[KCP](https://github.com/skywind3000/kcp) as the state of the art.

I chose ENet solely based on its unrivaled popularity. I chose KCP because it
claims to be state of the art and has significant adoption.

QUIC is excluded because it does not claim to be designed for this use case and
measuring protocols takes work.


### Limitations of Comparison

Comparing protocols is complicated because protocols are complicated.

A route between two sockets, which the protocols compared in the following
benchmarks build on top of, is stateful and opaque. At any given time it has a
certain amount of bandwidth available, a certain latency to deliver the packets,
and probabilities of re-ordering and dropping packets. None of these attributes
are simple to measure, independent of each other, or independent of the behavior
of the protocol attempting to adapt to them.

For a fun example, what do you think will happen to a TCP connection that is
sending 400 byte payloads at 60 Hertz on a connection with a router in the
middle that has an outgoing token buffer filter rate limit of 200kbps (not
enough) but no MTU and an unlimited queue size? The graph below illustrates the
round trip time in milliseconds for these periodic payloads against the index of
the payload.

![tcp growth](/assets/tcp_growth.gif)

As TCP sends more data than the rate limit will allow to pass without delay, the
payload takes longer to arrive and ACK, but the payload does arrive and doesn’t
drop. TCP adjusts to the delay by sending a larger packet. Because of the rate
limit, the larger packet takes even longer to arrive. This repeats indefinitely;
packets endlessly grow in size and take longer to arrive. The last packet sent
on this chart was 32,834 bytes.

This combination of variables and many others that are easy to imagine will
simply break protocols. The scenario demonstrated here obviously does not occur
in real life, but a protocol designer has to know whether a scenario will occur,
and how often, in many non-obvious cases.

Protocol designers must not only identify and accommodate most realistic network
conditions, but also transitions between them. Even if the tech along the route
behaves deterministically, the other users sharing the route will not. There
will be bursts of packet loss, packet reordering, and router queuing delay.

On the other side, a protocol user’s send patterns can be completely
inappropriate for the network conditions and the protocol designer must decide
how to moderate their behavior.

The point I make here is that the performance of a protocol is a function of the
conditions, and those are as diverse as real numbers. Any meaningful comparison
of protocols is hyper specific and predictive only in similar conditions.


### Benchmark

The benchmark is run in two network conditions:



*   Normal
    *   Bandwidth: 1.05Mbits/s
    *   Round Trip Time: mean 27.484 ms, deviation 9.739 ms
    *   Packet Loss: ~0%
    *   Implementation: Residential connection to a remote VPS
*   Turbulent
    *   Bandwidth: 1.05Mbits/s
    *   Round Trip Time: mean 27.484 ms, deviation 9.739 ms
    *   Packet Loss: 10%, with 25%
        [correlation](https://wiki.linuxfoundation.org/networking/netem?utm_medium=twitter&utm_source=twitterfeed#packet_loss)
    *   Implementation: Residential connection to a remote VPS, with Linux
        traffic control modifications to the outbound queue of the network
interface of the benchmark client

The benchmark client periodically sends payloads of 400 bytes at 60 Hertz to a
server. The server simply sends the payloads back. We measure the round trip time.

See the [full
datasheet](https://docs.google.com/spreadsheets/d/12OemlDCDSaWygtYKG6TcOACPjfgwjfw40F5_-qi-ypU/edit?usp=sharing)
and [benchmark code](https://github.com/turnage/miknet/tree/master/bench).

<iframe width="632" height="391" seamless frameborder="0" scrolling="no"
src="https://docs.google.com/spreadsheets/d/e/2PACX-1vSg30OZuxM2lZcNBehn2nwXfXi3XCYx0MGNhBD43YNgOW5dIDtKnBEVhpT8M_OSvuo-TJVrM0P1AtcN/pubchart?oid=1470078334&amp;format=image"></iframe>

In the simulation of normal conditions, both KCP and ENet maintain lower and
less variant latency than TCP.

ENet consistently holds lower and less variant latency than KCP. ENet’s mean
latency over 10 runs is 26.297ms (deviation 9.693ms) where KCP Turbo’s mean
latency over 10 runs is 37.074ms (deviation 11.218ms). ENet round trips the
payload in 71% of the time it takes KCP to round trip the same payload. 

<iframe width="647" height="371" seamless frameborder="0" scrolling="no"
src="https://docs.google.com/spreadsheets/d/e/2PACX-1vSg30OZuxM2lZcNBehn2nwXfXi3XCYx0MGNhBD43YNgOW5dIDtKnBEVhpT8M_OSvuo-TJVrM0P1AtcN/pubchart?oid=1743140131&amp;format=image"></iframe>

In the turbulent conditions, only KCP Turbo avoids significant latency spikes.
KCP Turbo holds significantly lower latency than ENet, with a mean round trip
time of 40.582ms (deviation 10.399ms). ENet’s mean round trip time was 139.306ms
(deviation 147.850ms). KCP Turbo round trips the payload in 29% of the time it
takes ENet to round trip the same payload.


### Conclusion

ENet’s reliable ordered streams achieve lower and less variant latency for
periodic payloads than KCP on unaltered connections I have observed in the
United States. Under high packet loss, KCP performs better than ENet by an
order.

KCP regresses to a fair proportion of bandwidth at a lower rate than ENet or
KCP, backing off at 1.5x rather than 2x, and it aggressively proactively
retransmits messages. If in the future KCP came to represent some meaningful
proportion of traffic, I wonder if these results would hold. I can’t imagine it
is in routers’ interests to reward this behavior, but I know little about
fairness enforcement.

A combined solution is interesting to consider: a user of ENet could respond to
congestion by reducing their send rate, or doubling down and
communicating over KCP. KCP holds much lower latency than ENet under high packet
loss, but at 10% loss it is still almost double what ENet gets without packet
loss. It's possible certain use cases could benefit from switching to KCP
instead of respecting the congestion.

