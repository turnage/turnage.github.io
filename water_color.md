# A Generative Approach to Simulating Watercolor Paints from “Scratch”

This post and the covered work were inspired by Tyler Hobb’s post [A Generative Approach To Simulating Watercolor Paints](http://www.tylerlhobbs.com/writings/watercolor). I came across it in April and decided to replicate it from scratch as a first project to build out my own generative art toolkit. This is a walk through of the fun!

I don't go into nearly sufficient detail for anyone to follow along step by step, but I hope to cover the basic ideas and provide links to resources so that if you do decide to implement what I describe, you can.

Here's a preview of some results:

![results](https://imgur.com/534O1j1.gif)

## Table of Contents
 
* [An image](#an-image)
* [Rendering polygons](#rendering-polygons)
	* [Representing polygons](#representing-polygons)
	* [Rastering polygons](#rastering-polygons)
	* [Super sampling polygons](#super-sampling-polygons)
	* [Using a gpu like a reasonable person](#using-a-gpu-like-a-reasonable-person)
* [Making polygons into watercolor](#making-polygons-into-watercolor)
	* [A regular n-gon to start](#a-regular-n-gon-to-start)
	* [Warping our n-gon](#warping-our-n-gon)
	* [Subdiving our n-gon](#subdividing-our-n-gon)
	* [Creating a watercolor splotch](#creating-a-watercolor-splotch)

## An image

We will render an image in this guide. To follow along find some library for the language you are using that allows you random access to pixels in an image buffer or on-screen. I used [repa](https://hackage.haskell.org/package/repa) in Haskell as a buffer and wrote out to a bitmap.

If you're totally unfamiliar with pixels: they are some tuple of values that represent a color and maybe an opacity. There are many ways of defining color but most common is the [rgb color space](https://en.wikipedia.org/wiki/RGB_color_space). For any given pixel you will have a 4-tuple: (red, green, blue, alpha). Google "color picker" to play around with the values and get a feel for it.

## Rendering polygons

In this chapter we will render a simple square.

![preview](https://i.imgur.com/5NDakXI.png)

### Representing polygons

First thing, let's get a polygon type to work with. For the purposes of this walkthrough we will use only closed polygons, so my polygon type looks like:

```haskell
data Point = Point
	{ x :: Double
	, y :: Double }

data Polygon = Polygon { verts :: V.Vector Point }
```
Where I assume that the last vertex connects with the first vertex to close the polygon.

We're using Doubles instead of integers (which would be all we need to organize pixels) because polygons are continuous, which will become relevant later.

### Rastering Polygons

Polygon rendering usually works through some variation of [scanline rendering](https://en.wikipedia.org/wiki/Scanline_rendering).

If we plot our polygon and imagine a line scanning horizontally across it, we can count the intersections it makes. See this illustration by Vierge Marie:

![scanline illustration](https://upload.wikimedia.org/wikipedia/commons/a/a0/Scan-line_algorithm.svg)

Look at polygon D and scanline a. Scanline a intersects D twice. If we follow it from left to right and consider at each value of x how many times it has intersected D, we have

* a long section where it has instersected D zero times
* a section where it has intersected D one time
* a section after exiting D where it has intersected D two times

This is the crux of scanline rendering: on pixels where we have intersected the polygon an odd number of times, we shade it as part of the polygon.

To start we will do this for every polygon: 

* Derive the edges of the polygon
* Preprocess edges for scanline rendering
* Calculate which edges will be active at each row
* Calculate how many of those edges have been passed at each pixel
* If number of those edges is odd, shade the pixel

I'll include some Haskell sample code below for guidance because I had a good deal of trouble understanding handwavy guides like this when I first implemented it.

#### Deriving Edges
```haskell
edges :: Polygon -> V.Vector (Point, Point)
edges Polygon { vertices } = V.zip vertices rotatedLeft
  where
    rotatedLeft = V.snoc (V.head vertices) $ V.tail vertices
```

#### Preprocess edges for scanline rendering

We need to know the slope and boundaries of each of the polygon's edges; the `ScanEdge` type we want to build must contain enough information to answer two questions:

* Is this edge intersected by a scan line at height y?
* Is this edge to the left of column of x?

You can discard edges with slopes of 0; edges parallel to the scanlines don't help.

I used this type:
```haskell
-- slope in the form of y = mx + b
data Slope
  = Slope { m :: Double
         ,  b :: Double}
  | Vertical Double -- for a vertical line keep a static x where the line lies

data ScanEdge = ScanEdge
  { high :: Double -- highest y coord of the edge
  , low :: Double -- lowest y coord of the edge
  , slope :: Slope
  }
```

Which makes the implementation of those two questions look like:
```haskell
inScanLine :: Double -> ScanEdge -> Bool
inScanLine scanLine ScanEdge {high, low, ..} =
  scanLine >= low && scanLine < high

passedBy :: Point -> ScanEdge -> Bool
passedBy Point {x, y} (ScanEdge {slope, ..}) =
  case slope of
    Slope {m, b} -> (y - b) / m < x
    Vertical staticX -> staticX < x
```

#### Shade a pixel
```haskell
inPoly :: Point -> Polygon -> Bool
inPoly point poly = odd $ V.length crossedEdges
  where
    crossedEdges = V.filter (passedBy point) activeEdges
    activeEdges = V.filter (inScanLine $ y point) $ edges poly
```
Once you know the pixel is in the polygon, you can shade it however you want!

### Super sampling polygons

If you implemented what I've described your square will look crisp, but start rendering some irregular polygons and you will see some janky diagonal lines that look like stairs:

![polygon_jank](https://i.imgur.com/8tQYll5.png)

This is because we've been treating pixels as shaded or unshaded for a given polygon; there will necessarily be boundaries on a diagonal line where a pixel passes our test and gets shaded while the neighboring pixel fails the test, creating a stair-like pattern, a result of [aliasing](https://en.wikipedia.org/wiki/Aliasing).

Earlier I mentioned that polygons are continuous and solving this problem requires treating them that way. When we render a polygon with our scan line algorithm, we sample a continuous space (a grid with infinite resolution where polygons live) and grab a sample of it for each unit of our discrete medium (a grid with finite resolution which is our image). Now we will *super* sample, meaning we will take more than one sample of the infinite grid per pixel.

Where before we took one sample and decided whether or not to shade the pixel, now we will take four evenly spaced samples per pixel and average the results. For example if three out of our four sub-pixel samples of the polygon are shaded, we color that pixel with 75% opacity.

There are many anti-aliasing methods to choose from, but this simple technique can turn those janky edges pictured above into the much less janky edges pictured below:

![less_jank](https://i.imgur.com/G9m1lkg.png)

Some steps are still visible here where the lines almost become parallel with ground (the worst case). You can take your pursuit of smooth polygons much further if that's your taste. [See here](http://mlab.uiah.fi/~kkallio/antialiasing/EdgeFlagAA.pdf) for a good start.

### Using a gpu like a reasonable person

You can follow the rest of this guide with a well written version of the above algorithm; I never had any problems rendering watercolor.

If you are hoping to use the algorithm for bigger things, implementing it in such a way that it can handle the amount of polygons you'll inevitably demand of it in the amount of time you'll want it to is a categorically different endeavor. I spent a great deal of time profiling and re-implementing this algorithm in different languages and never achieved the throughput & latency goals I had.

Luckily you can instead just do the reasonable thing and use a gpu! I won't cover that in this post but the basics are:

1. [Tessellate your polygon](https://en.wikipedia.org/wiki/Polygon_triangulation) into triangles because most gpu APIs render only triangles.
2.  Write shaders for the graphics card to color the triangles.

See [The Book of Shaders](https://thebookofshaders.com/) for a good introduction and the [OpenGL wiki](https://www.khronos.org/opengl/wiki/Main_Page) (or the docs for [Vulkan](https://www.khronos.org/vulkan/) if you've got shiny hardware) to get dirty.

### Making polygons into watercolor

In this chapter we will make our polygons into water color through a series of deformations of the original polygon.

#### A regular N-gon to start

Let's start with a simple regular n-gon. A regular n-gon is a polygon whose n vertices are evenly spaced on the circumference of a circle:

![regular_ngon](https://i.imgur.com/soFcGEB.gif)

Let's make a function to get a point on the circumference of a circle at a given angle:

```haskell
circumPoint :: Point -> Double -> Double -> Point
circumPoint Point {x, y} radius angle = Point {x = x', y = y'}
  where
    x' = x + radius * (cos angle)
    y' = y + radius * (sin angle)
```

Using this we can make a regular n-gon by taking n points on the circumference of our circle.

```haskell
ngon :: Double -> Int -> Point -> Poly
ngon radius n centroid = Poly { vertices = V.generate n vertex}
	where
		vertex i = circumPoint centroid radius $ angle i
		angle i = (fromIntegral i) * interval
		interval = (2 * pi) / (fromIntegral n)
```

#### Warping our N-gon

Our water color simulation is built using a warp function, which wiggles the vertices of a polygon randomly on a Gaussian distribution.

The algorithm:

1. For each vertex:
	1. Generate a random offset by sampling a Gaussian distribution.
	2. (Optionally) Change the sign of the offset so it always moves the vertex _out_ from the polygon centroid.
	3. Scale the offset to the local strength.

Our local strength will be the distance between the vertex's surrounding neighbors. So when warping B in vertex set A -> B -> C, our local strength is the distance between A -> C; this should be the upper bound on the vertex's offset.

Here's how it ought to look, applying it to the polygon recursively:

![warp](https://i.imgur.com/6v3O85D.gif)

#### Subdividing our N-gon

The next core piece of our water color simulation is subdivision of our polygon. For each edge, we want two edges that compose the original edge.

The algorithm:

1. For every edge A -> C
2. Find midpoint B
3. Generate two edges, A -> B and B -> C

The polygon's shape shouldn't change. Here's an illustration of subdividing recursively with vertices highlighted:

![subdivision](https://i.imgur.com/0e6UcB0.gif)

#### Creating a watercolor splotch

We create layers of the watercolor by combining these two functions and applying them recursively:

![watercolor_layer](https://i.imgur.com/ktiVSnH.gif)

Once we have this layer we composite it by:

1. Duplicate it 30-100 times.
2. Decrease opacity to 2-4%.
3. Apply the warp function 4-5 more times to each duplicate.

![splotch](https://i.imgur.com/DJJknRA.png)

You will find different results depending on the order in which you apply subdivision and warp functions.

You can also change the spread of different areas by adding to your local strength factor a strength value associated with each vertex in the base polygon. This means some areas will spread out more than others. You can get finer edges by subdividing more often than warping.

You can also start from the base polygon at each layer instead of working with duplicates of a pre-warped layer. This is my favorite method:

![multilayer](https://i.imgur.com/JUEgeRy.png)

Or you could make the vertex offsets pull inward toward the polygon centroid instead of outward:

![inward](https://i.imgur.com/BLrwPUp.png)

That's it! There are too many variants of these rules to go over, so I'll leave them to explore.

[Here's a piece](https://www.instagram.com/p/BdhSOjAF3FV) I made with an implementation of this algorithm in my toolkit [valora](https://github.com/turnage/valora).

If you have questions feel free to ping me on Reddit at [/u/roxven](https://www.reddit.com/user/roxven)! 