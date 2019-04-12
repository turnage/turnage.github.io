+++
title = "Generating Art With Haskell"
date = 2018-05-26
description = "An introduction to generating Art with Haskell"
draft = false
aliases = ["writing/2018-06-05-generating-art-with-haskell"]

[extra]
rss_include = true
+++

This article is an introduction to writing [generative art](https://en.wikipedia.org/wiki/Generative_art) with Haskell, using a stack inspired by [Ben Kovach's similar post](https://www.kovach.me/posts/2018-03-07-generating-art.html) I came across in March. If you plan to follow along see the [deps list](#dependencies-to-follow-along). I assume familiarity with Haskell and an interest in generative art.

<div class="img_row">
  <img class="col one_third" src="https://i.imgur.com/fpN2AGO.png" title="Seed 347593857234897520"/>
  <img class="col one_third" src="https://i.imgur.com/xWFQL0Z.png" title="Seed 99924583058"/>
  <img class="col one_third" src="https://i.imgur.com/atuesRr.jpg" title="Seed 98239276903311"/>
</div>

<p class="caption">
  Some images generated using the methods described below. <a href="https://paytonturnage.com/writing/2018-05-26-iterating-to-rainbow-strokes/">Details</a>.
  </p>


## Table of Contents

* [Vector Graphics with Cairo](#vector-graphics-with-cairo)

	* [Render Monad](#render-monad)

	* [Paths](#paths)

	* [Mattes](#mattes)

* [Generate Monad](#generate-monad)

* [Colour](#colour)

* [Animations](#animations)

* [Further Reading](#further-reading)

* [Raster Graphics with Accelerate](#raster-graphics-with-accelerate)

* [Dependencies To Follow Along](#dependencies-to-follow-along)

<br>

## Vector Graphics with Cairo

Axel Simon and Duncan Coutts wrote a [wonderful Cairo binding](http://hackage.haskell.org/package/cairo) for Haskell. We can use it to describe a 2D vector graphics composition and raster it. It may be helpful to keep the [haddock](http://hackage.haskell.org/package/cairo/docs/Graphics-Rendering-Cairo.html) open aside this introduction.

### Render Monad

At a high level, Cairo paints **source patterns** onto **surfaces** using instructions contained in a **Render** monad.

Source patterns may be a solid color, another surface, or as we'll cover in the matte section, another Render monad.

Surfaces are usually memory buffers or image files.

In this simple example code we create an image surface and realize two Render monads to create the image that follows.

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=Main1.hs"></script>

![](https://i.imgur.com/VK3YHNH.png)

Both monads in the example code above follow the typical structure we'll use moving forward. Each drawing action is made of

1. A source (````setSourceRGBA 0 0 0 1````)
2. A path (````rectangle 0 0 500 500````)
3. A draw instruction (````fill````)

Draw instructions always use the current path in the Render monad.


### Paths

There are some shortcuts for making paths, such as ````rectangle````, but usually we will need to use some combination of the path building Render monads ````moveTo````, ````lineTo````, ````curveto````, and ````closePath````.

Since Cairo is low level, you may want to build some types over these things. I personally use a Contour type which holds a vector of points, each represented by the [V2 type](http://hackage.haskell.org/package/linear-1.20.7/docs/Linear-V2.html) from the [linear](http://hackage.haskell.org/package/linear) package. V2 defines many useful class instances for relevant math and many other haskell libraries expect V2, so using it will make life easy.

Here is an example program that draws a triangle with the Contour type.

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=Main2.hs"></script>

![](https://i.imgur.com/CEF9Btu.png)

### Mattes

Cairo supports using a [stack of Render monads](https://hackage.haskell.org/package/cairo-0.13.5.0/docs/Graphics-Rendering-Cairo.html#v:pushGroupWithContent) for compositing. This means you can push a Render monad, bind some instructions, then pop it as a source for drawing your next paths. Here's an alpha matte function as an example:

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=Compositing.hs"></script>

This function creates a Render monad which draws ````src````, multiplying (in 0-1 space) the alpha channel of ````src```` with the alpha channel of ````matte````.

For example, with this matte:

![](https://i.imgur.com/KMLyLBb.png)

And this source:

![](https://i.imgur.com/zsg0mie.png)

````alphaMatte matte source```` looks like this:

![](https://i.imgur.com/dLyxKQV.png)

<br>

## Generate Monad

Originally described by Ben Kovach, the Generate monad helps us abstract the render instructions from the output. Ours will be different from Ben's, to remove IO effects (Render is an instance of MonadIO).

### Dimension Agnosticism

First, we can create a Reader monad to hold our width, height, and a scale factor. Then we can make our sketches agnostic to the final render dimensions using Cairo's ````scale```` function which will transform our coordinate space. For instance, you can work in a 500x500 grid and if you like the result, sink the time to render an image with identical content at scale factor 10 for a 5000x5000 output.

Running the Generate monad will yield a Render monad we can use. I recommend this over making Render part of a monad transformer stack in Generate. As you build up abstractions over different pieces of Cairo you may want to return other types in a Generate monad, at which point it will be nice to know those functions don't have side effects on the drawing or perform IO.

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=Main3.hs"></script>

Both of the following images were rendered with the above code; I only changed the arguments to ````World```` between them.

![](https://i.imgur.com/tcefhrb.png)

![](https://i.imgur.com/WNga6NL.png)

<br>

### Random Variables

We can add random variable support to our generate Monad using [rvar](http://hackage.haskell.org/package/random-source), [random-source](http://hackage.haskell.org/package/random-source), and [random-fu](https://hackage.haskell.org/package/random-fu), a comprehensive random variable library family written by James Cook and maintained by Dominic Steinitz. It implements most distributions you might want, and many you never will.

We'll put our Reader monad in a State transformer, then we can sample random variables when building our Render monads.

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=Main4.hs"></script>

Now the box we render will have a random color each invocation:

![](https://i.imgur.com/O6XUbZR.png)
![](https://i.imgur.com/3RDKa66.png)

<br>

## Colour

Colour in Cairo is interesting because it's sometimes important to work with it as colour in particular and other times it should just be treated as a source--identical to patterns and images you might paint with.

I settle on using [colour](https://hackage.haskell.org/package/colour) when working with colours themselves, and using a class for CairoColour that supports whatever I might use as a source:

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=Colour.hs"></script>

It may seem like unnecessary indirection, but it allows some convenient instances to be passed around such as for radial ramps:

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=RadialInstance.hs"></script>

<br>

## Animations

We can render animations in two ways:

1. If everything is derivable from the time or frame number, just slap a frame field in your World record and you're done!
2. If you need to carry state between frames (e.g. for a walker), wrap the Generate monad in a State monad.

This code renders frames to show the second method. I use ````convert *.png out.gif```` to stitch them together.

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=Main5.hs"></script>

![](https://i.imgur.com/gNUGDOS.gif)

Here's an animation I wrote using this technique:

<blockquote class="instagram-media" data-instgrm-permalink="https://www.instagram.com/p/BhDAA6GllYU/" data-instgrm-version="8" style=" background:#FFF; border:0; border-radius:3px; box-shadow:0 0 1px 0 rgba(0,0,0,0.5),0 1px 10px 0 rgba(0,0,0,0.15); margin: 1px; max-width:658px; padding:0; width:99.375%; width:-webkit-calc(100% - 2px); width:calc(100% - 2px);"><div style="padding:8px;"> <div style=" background:#F8F8F8; line-height:0; margin-top:40px; padding:50% 0; text-align:center; width:100%;"> <div style=" background:url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAMAAAApWqozAAAABGdBTUEAALGPC/xhBQAAAAFzUkdCAK7OHOkAAAAMUExURczMzPf399fX1+bm5mzY9AMAAADiSURBVDjLvZXbEsMgCES5/P8/t9FuRVCRmU73JWlzosgSIIZURCjo/ad+EQJJB4Hv8BFt+IDpQoCx1wjOSBFhh2XssxEIYn3ulI/6MNReE07UIWJEv8UEOWDS88LY97kqyTliJKKtuYBbruAyVh5wOHiXmpi5we58Ek028czwyuQdLKPG1Bkb4NnM+VeAnfHqn1k4+GPT6uGQcvu2h2OVuIf/gWUFyy8OWEpdyZSa3aVCqpVoVvzZZ2VTnn2wU8qzVjDDetO90GSy9mVLqtgYSy231MxrY6I2gGqjrTY0L8fxCxfCBbhWrsYYAAAAAElFTkSuQmCC); display:block; height:44px; margin:0 auto -44px; position:relative; top:-22px; width:44px;"></div></div><p style=" color:#c9c8cd; font-family:Arial,sans-serif; font-size:14px; line-height:17px; margin-bottom:0; margin-top:8px; overflow:hidden; padding:8px 0 7px; text-align:center; text-overflow:ellipsis; white-space:nowrap;"><a href="https://www.instagram.com/p/BhDAA6GllYU/" style=" color:#c9c8cd; font-family:Arial,sans-serif; font-size:14px; font-style:normal; font-weight:normal; line-height:17px; text-decoration:none;" target="_blank">A post shared by Payton Turnage (@venlute)</a> on <time style=" font-family:Arial,sans-serif; font-size:14px; line-height:17px;" datetime="2018-04-01T23:50:06+00:00">Apr 1, 2018 at 4:50pm PDT</time></p></div></blockquote> <script async defer src="//www.instagram.com/embed.js"></script>

<br>

## Further Reading

If you've decided to start writing art with Haskell, hurray! Here are some good readings for your journey.

* [Working With Color in Generative Art](http://www.tylerlhobbs.com/writings/generative-colors) by Tyler Hobbs
* [On Generative Algorithms](https://inconvergent.net/generative/) by Anders Hoff
* [Probability Distributions for Algorithmic Artists](http://www.tylerlhobbs.com/writings/probability-distributions-for-artists) by Tyler Hobbs
* [A Story of Iteration](https://www.kovach.me/posts/2018-04-30-blotch.html) by Ben Kovach

If you make something, come share your work at [/r/generative](https://www.reddit.com/r/generative)! We're friendly!

<br>

## Raster Graphics with Accelerate

*WARNING: This is an esoteric thing you're about to try. No one supports it or maintains any code to help you do it. You may waste lots of time. Here I share my unsupported undocumented minimally tested code I use to do it, with token commentary.*

At some point you may want to manipulate pixel values, or generate something per-pixel as in a shader (e.g. a noise texture). This is difficult to do with Cairo, but with a little black magic and by leveraging some careful work done by people who understand color spaces well, we can build a GPU accelerated per-pixel function to modify our Cairo surface.

If you use Cairo's 32 bit surface format (you should use Cairo's 32 bit surface format), the surfaces contain 8 bits per channel and the colors are premultiplied by the alpha. The colors are in sRGB space.

You can acheive a reasonable compositing flow by unpacking this data into something you can work with, doing your shading work, and packing it back down, though getting the colors and data format right can be a bit tricky. See [imageSurfaceGetPixels](https://hackage.haskell.org/package/cairo-0.13.5.0/docs/Graphics-Rendering-Cairo.html#v:imageSurfaceGetPixels) for a start.

Below is my personal solution with some parts stripped out. Basically this file provides a function which accepts an [accelerate](http://www.acceleratehs.org/index.html) metaprogram which computes a color for each pixel, given some uniforms and random access to what's already been drawn. Then I run it on GPU and put the results back in the Cairo surface.

<script src="https://gist.github.com/turnage/a949ff777ad04871251fb197152faa94.js?file=Shade.hs"></script>

<br>

## Dependencies to Follow Along

Slap these in your hpack list and `stack solver` away!

````
- cairo
- colour
- vector
- random-source
- random-fu
- mtl
- rvar
- transformers
- linear
````

If you plan to do raster graphics on your GPU as described, follow accelerate's [getting started](http://www.acceleratehs.org/get-started.html).






