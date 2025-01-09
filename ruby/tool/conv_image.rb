#! /usr/bin/env ruby

require 'rmagick'
include Magick

CROP_X = 136
CROP_Y = 0
CROP_WIDTH = 2264
CROP_HEIGHT = 1027

RESIZE_WIDTH = 720
RESIZE_HEIGHT = 494  # RESIZE_WIDTH * 3 / 4

fns = Dir.glob(',img/*.png')
fns.each do |fn|
    dstfn = ",dst/#{File.basename(fn)}"
    img = ImageList.new(fn)
    img.crop!(CROP_X, CROP_Y, CROP_WIDTH, CROP_HEIGHT)
    img.resize!(RESIZE_WIDTH, RESIZE_HEIGHT)
    img.write(dstfn)
end
