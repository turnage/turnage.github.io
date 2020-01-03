+++
title = "Packing Circles with Quad Trees"
date = 2019-03-17
description = "A walkthrough of packing circles with Processing"
draft = false
aliases = ["writing/2019-03-17-circle-packing-quad-trees"]

[extra]
rss_include = true
+++

This article describes a technique for circle packing using quad
trees. All snippets are written in Haskell. For some
context on circle packing, see my [beginner article on the topic](./writing/2019-03-17-circle-packing.md).

Prerequisites:
1. Some reading on quad trees.
    * [Interactive Tutorial](https://jimkang.com/quadtreevis/)
    * [Wikipedia](https://en.wikipedia.org/wiki/Quadtree)
2. Enough programming experience to translate my prose and
    Haskell snippets to real code.


<div class="img_row">
  <img class="col half" src="/assets/YGtcMYs.gif" title="Seed 347593857234897520"/>
  <img class="col half" src="/assets/nsNn1kV.gif" title="Seed 99924583058"/>
</div>

<p class="caption">Some images generated using the methods described in this article.</p>

A quad tree is good for searching 2D space, which is exactly what we want to do when we're checking
whether a circle we are about to place overlaps with an existing circle. Why should we bother
comparing our little circle in the bottom left of the frame for overlaps with all the little circles
in the top right of the frame? There's no way they overlap! As we pack more circles, that wasted
effort becomes seconds, minutes, or hours of our time.

To make checking circles for collision faster, we'll build a quad tree that can answer "what is the
nearest circle in the tree to this given circle?"

```haskell
data Circle = Circle (V2 Double) Double

nearest :: QuadTree Circle -> Circle -> Maybe Circle
```

Once we define that function we can check for validity the usual way:

```haskell
overlap :: Circle -> Circle -> Bool
overlap (Circle c1 r1) (Circle c2 r2) = d - (r1 + r2)
  where
    d = distance c2 c2

valid :: QuadTree Circle -> Circle -> Bool
valid tree c = fromMaybe True overlaps
  where
    overlaps = fmap ((>0) . (overlap c)) nearest
    nearest = nearest tree c
```

## Building The Tree

To build our tree, we'll insert the centers of circles we've placed. They'll go into the region
where they belong just like any point-region quad tree, but we'll keep an association with the
radius of the circle too. So our leaf type is just the `Circle` type we defined above.

Unfortunately a straight-up depth first search of this tree will not work; the nearest circle center
in the tree is not necessarily the nearest point in 2D space, or nearest circle. This is because

1. There may be a small circle at the edge of neighboring quadrant which closer than any circle in the
   search quadrant.
2. There may be a large circle in a neighboring quadrant whose edge is closer than any circle in the
   search quadrant.

I've used my MSPaint skills to explain (the green circle is the one we are querying the tree for the
nearest neighbor of):

![](/assets/xLeunQT.gif)

The smaller circle in the query circle's quadrant will be closer in the tree, but the larger circle
in a neighboring quadrant is actually closer.

What we'll need to do is, when building the tree, tag each quadrant with the largest circle it
contains and ensure that stays up to date. That will enable the search technique in the next section.

## Searching the tree.

Then, we can search breadth first with two steps at each
level:

1. Find the closest circle at this level.
2. Choose eligible subtrees to search on the next iteration.

### The Closest Circle

To find the closest circle at a level in tree we build a set of candidates composed of

1. The closest circle we've found so far.
2. All of the circles at this level in the tree.
3. All of tags on the subtrees at this level.

We take these candidates and select the closest one to the query circle by comparing each
circle's distance to our query circle using the distance function we defined earlier. This is
our new "closest circle so far".

### Eligible Sub-Trees

For the next iteration, we want to search subtrees which meet the following criteria:

The distance between the _boundary of the subtree region_ and center of the query circle is less
than the sum of the radii of the query circle and the region's largest circle (the one that should
be cached in its tag).

This is because the quad may at some depth contain an overlapping circle if the largest
circle in it is positioned perfectly at the edge nearest the query circle.

We don't need to consider the nearest circle so far because our tree has an invariant that no
circles in it overlap.

```haskell
data Rect = Rect
    { topLeft :: V2 Double
    , width :: Double
    , height :: Double
    }

data Quad = Quad
    { largestContainedCircle :: Maybe Circle
    , bounds :: Rect
    , children :: ( Maybe QuadTree
                  , Maybe QuadTree
                  , Maybe QuadTree
                  , Maybe QuadTree)
    }

-- Given the nearest circle found so far, returns
-- whether the quad is eligible for further search
-- (i.o.w. it might have a nearer circle to the
-- query circle at some lower level).
eligible :: Circle -> Circle -> Quad -> Bool 
eligible n query@(Circle c r) (Quad l b _) = case l of
    Just (Circle _ lr) ->
        let distanceToBounds = distanceToRect b c
            closeAsPossible = distanceToRect - (r + lr)
         in closeAsPossible < distance query n

-- Calculates the distance from a point to any point
-- on the perimeter of a Rect by taking the max of
-- the point's distance to any line that composes
-- the perimeter.
distanceToRect :: Rect -> V2 Double -> Double
distanceToRect r@(Rect (V2 tlx tly) w h) (V2 x y) =
  let xc1 = tlx + w
      xc2 = tlx
      yc1 = tly + h
      yc2 = tly
      xDist = max 0 $ max (x - xc1) (xc2 - x)
      yDist = max 0 $ max (y - yc1) (yc2 - y)
   in norm (V2 xDist yDist)
```

## Results and Applications

If you implement this and compare it with the `N^2` stochastic search method from the
beginner tutorial you should find your wait times much lower! I packed the following
100,000 circles in under 1 second using this method!

![](/assets/FBk7AAB.gif)

For simply packing circles this algorithm is probably not worth it; packed circles are
packed circles. But generally fast collision detection solutions will become a lot easier
to whip up if you work out an intuition for quad trees; I created the outlines in this image by
creating a path around the box of circles and incrementally moving the points of the path inward
until they collided with a circle--which would have been prohibitively slow to explore with the
stochastic search method.