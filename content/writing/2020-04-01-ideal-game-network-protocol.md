+++
title = "The Ideal Game Network Protocol"
date = 2020-04-01
description = "An investigation of game network protocols"
draft = false
aliases = []

[extra]
rss_include = true
+++

Online multiplayer games are similar to correspondence chess. When a player
receives a message with the distant player’s move, they represent it on their
own board. It feels to the players as if they were playing on one board
together. Netcode for an online game needs to build the same illusion.

### Prioritizing Traffic

Modern consumer networks can’t provide the bandwidth and latency necessary to
just naively sync all players to the entire complex game world. This makes
netcode hard, and the solutions invariably require two features from transport
protocols: low deterministic latency, and the ability to prioritize among
outbound network traffic.

To understand why netcode needs to prioritize, consider a game with these update
streams: updates to objects near the player, and a download of a city on the map
they haven’t visited yet. The map download needs to happen eventually, but
should never inhibit the player’s experience unnecessarily. This is one of many
situations in which a netcode author would want to prioritize some classes of
traffic over others.


### Why Protocol Designers Build on UDP


#### Protocol Designers Must Build on TCP or UDP

New protocols have little choice but to build on TCP or UDP if they have any
hope of deployment in under ten years. The successor to both,
[SCTP](https://en.wikipedia.org/wiki/Stream_Control_Transmission_Protocol), has
been a standard for over a decade, but it is still impractical to use on the
internet because most routers don’t support it, either due to explicit filters
or [NAT problems](https://tools.ietf.org/html/draft-ietf-behave-sctpnat-05).

This is also why [HTTP3](https://en.wikipedia.org/wiki/HTTP/3) runs on UDP: so
it can actually deploy.


#### TCP Does not Support Prioritization

If a game sent its important real time updates and its preemptive map downloads
on TCP, dropped or delayed packets containing the map could degrade the latency
of the real time updates. This is called [head of line
blocking](https://en.wikipedia.org/wiki/Head-of-line_blocking). TCP suffers from
it because it has a single ordered stream for all data. Netcode authors can’t
tell TCP how to prioritize outbound network traffic.

Consider these simulation results comparing TCP to a popular game networking
library, [ENet](http://enet.bespin.org/). In the simulation, a priority stream
of 200 byte payloads is updated at 60Hz on a round trip between two endpoints on
a simulated wire that drops 5% of packets. The results are round trip times for
the priority payload. A concurrent bulk data transfer is sent alongside the
periodic messages. \



<table>
  <tr>
   <td><strong>Concurrent Transfer</strong>
   </td>
   <td><strong>TCP</strong>
   </td>
   <td><strong>ENet</strong>
   </td>
  </tr>
  <tr>
   <td><strong>0</strong>
   </td>
   <td>604.523µs
   </td>
   <td>1.679989ms
   </td>
  </tr>
  <tr>
   <td><strong>800 bytes, 240Hz</strong>
   </td>
   <td>22.748024ms
   </td>
   <td>1.770451ms
   </td>
  </tr>
</table>


Where TCP must interleave all data on a single ordered stream, ENet allows us to
specify that streams are independent of one another; the higher priority
messages can continue surfacing to the receiver even if the bulk transfer stream
is waiting. As a result, the periodic messages sent on ENet do not suffer
latency degradation like they do on TCP.

It is possible to do this work on top of TCP to realize some gains.
[HTTP2](https://en.wikipedia.org/wiki/HTTP/2) is a protocol that mixes bytes
from multiple HTTP requests on top of TCP so they don’t block each other. This
is called [multiplexing](https://en.wikipedia.org/wiki/Multiplexing).

Multiplexing on TCP can solve the head of line blocking problem at the
application layer. Head of line blocking at the transport layer was still enough
of a problem that [HTTP3](https://en.wikipedia.org/wiki/HTTP/3) takes it a step
further and multiplexes over UDP. [This tech
talk](https://www.youtube.com/watch?v=hQZ-0mXFmk8) is a high level overview of
the HTTP3 design that may help put some of these issues in context.


#### TCP is Latent 

TCP is not a slow protocol. Most implementations of reliable ordered streams are
comparatively latent in practice.

Not all of this earned. In addition to filtering out unrecognized protocols,
routers will compromise on the other protocols they accept before TCP. When the
buffers are full, UDP packets get kicked out first because TCP packets are more
likely to result in retransmission. 

There is however a place TCP will not go, and all it takes to beat TCP latency
is go there: lower the throughput. TCP always wants the wire filled with as much
unique data as it can carry, but games don’t have that much data. Netcode
usually uses small (1-300 byte) periodic messages. If a game runs at 60Hz,
that’s ~16ms every frame where the netcode has nothing to say, so why would a
game network protocol care about throughput?

The simplest way to improve on TCP latency is to use the extra wire space to
send redundant data. There are a variety of ways to do this, from pre-emptively
remediating dropped packets with forward error correction to just not backing
off when packets start to drop, because wire space for retransmissions remains.

An example from ENet is that it will continue to retransmit data in the face of
much higher drop rates compared to TCP. The table below contains statistics on
round trip time for a 200 byte payload sent in a reliable ordered stream at
60Hz. The simulated wire is configured to drop packets at different rates with
20%
**[correlation](https://wiki.linuxfoundation.org/networking/netem?utm_medium=twitter&utm_source=twitterfeed#packet_loss)**.
Results show round trip times for the payload. While TCP backs off and sends
less data as the packet drop rate increases, ENet continues to retransmit,
lowering the latency.


<table>
  <tr>
   <td><strong>Drop Rate</strong>
   </td>
   <td><p style="text-align: right">
<strong>TCP</strong></p>

   </td>
   <td><p style="text-align: right">
<strong>ENet</strong></p>

   </td>
  </tr>
  <tr>
   <td><strong>0%</strong>
   </td>
   <td><p style="text-align: right">
Mean 412.013µs</p>

<p>
<p style="text-align: right">
Deviation 62.612µs</p>

   </td>
   <td><p style="text-align: right">
Mean 1.460ms</p>

<p>
<p style="text-align: right">
Deviation 401.566µs </p>

   </td>
  </tr>
  <tr>
   <td><strong>10%</strong>
   </td>
   <td><p style="text-align: right">
Mean 14.002ms</p>

<p>
<p style="text-align: right">
Deviation 54.793ms</p>

   </td>
   <td><p style="text-align: right">
Mean 1.458ms</p>

<p>
<p style="text-align: right">
Deviation 376.478ms</p>

   </td>
  </tr>
  <tr>
   <td><strong>20%</strong>
   </td>
   <td><p style="text-align: right">
Mean 56.579ms</p>

<p>
<p style="text-align: right">
Deviation 85.311ms</p>

   </td>
   <td><p style="text-align: right">
Mean 37.204ms</p>

<p>
<p style="text-align: right">
Deviation 120.387ms</p>

   </td>
  </tr>
</table>



### Why not Combine UDP and TCP?

TCP dynamically calibrates itself to maximize usage of the wire, watching for
its own dropped packets as a signal of reaching capacity. The problem with that
when using TCP and UDP in parallel is that a router will drop UDP packets at a
higher rate than TCP packets when under load. As a result, when the TCP
connection sends lots of data it will [induce packet
loss](https://web.archive.org/web/20160103125117/https://www.isoc.org/inet97/proceedings/F3/F3_1.HTM)
on the outbound UDP traffic.

These protocols can be combined, but a healthy combined solution is not simple.
Bandwidth must be rationed between the two, and that is something hard enough to
measure that the tradeoffs against a well designed UDP based protocol are rarely
appealing.


### Classes of Traffic

We’ve established that different classes of network traffic in online
multiplayer games need to be treated differently. What the traffic actually
looks like varies between games of course, but at the transport layer the
traffic falls into two basic classes.

**Supercedable** packets, such as player positions in an FPS, are immediately
superseded by the next packet of their kind. Dropped packets of this class do
not require remediation.

These should be delivered unreliably, but sequenced: packets are sent, but not
retransmitted if dropped. The receiver is guaranteed to receive packets at most
once, and in sequence. For example the receiver may see packets 1, 2, 4, 8, 9, …

**Causal** packets, such as player input in an RTS, influence
the meaning of all later packets and will not be superseded. Dropped packets of
this class require remediation, and there is no benefit to receiving later
packets if old ones are missing.

These should be delivered reliably and in order: packets are sent, and
retransmitted if dropped. The receiver is guaranteed to receive packets in
order. The receiver will see packets 1, 2, 3, 4, 5, …

Any general game network protocol must support at least these two delivery
methods, and allow the creation of independent streams.

Another notable method is reliable unordered delivery. This is the best method
for big data transfers that can’t be used until they are complete; for example it doesn’t
matter which chunks of the map arrive in what order, they just all need to
arrive to complete it. In practice libraries often expose this as “delivering
arbitrarily large packets” and handle the fragmentation internally. A user would
just open a new reliable ordered stream and dump the data block.


### The Ideal Game Network Protocol

Anyone who has ever played an online game would agree the present situation is
not perfect. How much of the room to improve is the network protocol’s to claim
remains to be seen.

The big picture of game networking also includes the netcode built on top of the
protocol and [all of the routers between players and the
server](https://technology.riotgames.com/news/fixing-internet-real-time-applications-part-i),
both of which are out of the protocol’s control. Bad netcode can perform badly
on the best protocol, and if players in Australia connect to a server in London
there is no negotiating with the speed of light traveling through optic cable.

Wherever the wire could facilitate better performance and the protocol does not
seize the opportunity is an area to improve.

I am currently [building a
tool](https://github.com/turnage/Miknet/tree/master/bench) to measure game
network protocols in simulated network conditions. That is where I gathered the
data in this post. I will continue to build simulations and integrate more
protocols into the suite. The ability to quickly test guesses about how these
protocols behave will hopefully help me investigate what the “ideal” protocol
looks like, if it exists.

Stay tuned with my [RSS Feed](https://paytonturnage.com/rss.xml) to follow the
investigation. This is how I am spending quarantine.

