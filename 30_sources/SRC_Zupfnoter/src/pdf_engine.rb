require 'opal-jspdf'
require 'harpnotes'

module Harpnotes

  class PDFEngine
    include Harpnotes::Drawing
    attr_reader :pdf

    PADDING = 4.0
    JUMPLINE_INDENT = 10.0
    DOTTED_SIZE = 0.3

    X_SPACING = 115.0/10.0

    def initialize()
      @pdf = JsPDF.new(:l, :mm, :a3)
      @pdf.x_offset = 0.0
    end


    def draw_in_segments(sheet)
      delta = -12.0 * X_SPACING # todo: 12.0 = number of strings per page
      @pdf = JsPDF.new(:p, :mm, [210, 287])
      @pdf.y_offset = -5
      addpage = false
      (0..2).each do |i|
        draw_segment(30 + i * delta, sheet, addpage) # todo: 30 = initial offset
        addpage = true
      end
      @pdf
    end

    def draw(sheet)
      # todo: move this to the layouter
      @pdf.rect(1.0, 1.0, 418, 295)
      @pdf.rect(0.0, 0.0, 420.0, 297.0)

      # the cutmarks are drawn in octave distance
      delta = 12.0 * X_SPACING
      (1..2).each do |i|
        [:top, :bottom].each { |border| draw_cutmarks(i, delta, border) }
      end

      sheet.children.each do |child|
        @pdf.line_width = child.line_width
        if child.is_a? Ellipse
          draw_ellipse(child) if child.visible?
        elsif child.is_a? FlowLine
          draw_flowline(child) if child.visible?
        elsif child.is_a? Harpnotes::Drawing::Glyph
          draw_glyph(child) if child.visible?
        elsif child.is_a? Harpnotes::Drawing::Path
          draw_path(child) if child.visible?
        elsif child.is_a? Harpnotes::Drawing::Annotation
          draw_annotation(child) if child.visible?
        else
          $log.debug "don't know how to draw #{child.class} (#{__FILE__} #{__LINE__})"
          nil
        end
      end

      @pdf
    end

    private

    def draw_annotation(root)

      #todo: reference to FONT_STYLE_DEF is not ok here.
      style = $conf.get('layout.FONT_STYLE_DEF')[root.style] || $conf.get('layout.FONT_STYLE_DEF')[:regular]
      mm_per_point = $conf.get('layout.MM_PER_POINT')

      @pdf.text_color = style[:text_color]
      @pdf.font_size = style[:font_size]
      @pdf.font_style = style[:font_style]
      # + style ... we shift it up by the fontsize converted from point to mm by mm_per_point
      @pdf.text(root.center.first, root.center.last + style[:font_size] * mm_per_point, root.text)
    end

    def draw_cutmarks(i, delta, border)
      vertical_pos = {:top => 7, :bottom => 290}[border] # [start_y, center_y, end_y]
      hpos = X_SPACING/2.0 + delta * i + 3 #todo: 3 is the background_size Default::Layout::ELLIPSE_SIZE[0]
      hdiff = X_SPACING/2.0

      center = Vector2d(X_SPACING/2.0 + delta * i, vertical_pos)
      size = 1

      @pdf.line((center + [-size,- size]).to_a, (center + [size,size]).to_a)
      @pdf.line((center + [-size, size]).to_a, (center + [size,-size]).to_a)
    end

    def draw_ellipse(root)
      style = root.filled? ? :F : :FD
      @pdf.fill = (0...3).map { root.filled? ? 0 : 255 }
      if root.rect?
        @pdf.rect_like_ellipse(root.center, root.size, style)
      else
        @pdf.ellipse(root.center, root.size, style)
      end

      if root.dotted?
        @pdf.fill = (0...3).map { 0 }
        @pdf.ellipse(root.center.zip(root.size).map { |s| a, b = s; a + b + 0.7 }, [DOTTED_SIZE, DOTTED_SIZE], :F)
      end
    end


    def draw_glyph(root)

      style = root.filled? :FD, :FD
      @pdf.fill = (0...3).map { root.filled? ? 0 : 255 }

      center = [root.center.first - root.size.first, root.center.last - root.size.last]
      #center = [root.center.first, root.center.last]
      background_size = root.size.map { |s| 2.0 * s }  # root.size is specified as radii for eclipse

      # draw a white background
      @pdf.fill = (0...3).map { root.filled? ? 0 : 255 }

      @pdf.fill = [255, 255, 255]
      @pdf.stroke = [255, 255, 255]
      @pdf.rect_like_ellipse(root.center, root.size, :FD)

      # draw th path
      #e = @pdf.lines(...)

      @pdf.fill = [0, 0, 0]
      @pdf.stroke = [0, 0, 0]

      scalefactor = background_size.last / root.glyph[:h]


      scale = [scalefactor, scalefactor]
      lines = []
      start = []
      root.glyph[:d].each do |element|
        case element.first
          when "M"
            @pdf.lines(lines, start.first, start.last, scale, "FD", false) unless lines.empty?
            lines = []
            start = [center.first + (element[1] + root.glyph[:w]/2) * scale.first,
                     center.last - (element[2] + root.glyph[:h]/2) * scale.last]
          when "l"
            lines.push element[1 .. -1]
          when "c"
            lines.push element[1 .. -1]
          when "z"
            @pdf.lines(lines, start.first, start.last, scale, "FD", true) unless lines.empty?
            lines = []
          else
            $log.error("BUG: unsupported command '#{element.first}' in glyph (#{__FILE__} #{__LINE__})")
        end
      end
      @pdf.stroke = [0, 0, 0]

      # add the dot if needed
      if root.dotted?
        @pdf.fill = (0...3).map { 0 }
        @pdf.ellipse(root.center.zip(root.size).map { |s| a, b = s; a + b * 1.5 }, [DOTTED_SIZE, DOTTED_SIZE], :F)
      end


    end


    # this draws a page setment
    def draw_segment(x_offset, sheet, newpage = false)
      @pdf.x_offset = x_offset
      @pdf.addPage if newpage
      draw(sheet)
    end

    #
    # Draw a Flowline to indicate the flow of the music. It indicates
    # the sequence in which the notes are played
    #
    # @param root [type] [description]
    #
    # @return [type] [description]
    def draw_flowline(root)
      #@pdf.draw = (0...3).map { root.dashed? ? 128 : 0 }
      @pdf.line_dash = 3 if root.dashed?
      @pdf.line_dash = 6 if root.dotted?
      @pdf.line(root.from.center, root.to.center)
      @pdf.use_solid_lines #if root.dashed? # reset dashing
    end

    #
    # Draw a Jump line to indicate that the music is to be continued at another beat
    # @param root [Drawing::Jumpline] The jumpline to be drawn
    #
    # @return [nil] nothing
    def draw_jumpline(root)
      startpoint = root.from.center.clone
      startpoint[0] += PADDING
      startpoint[1] -= PADDING/4.0

      endpoint = root.to.center.clone
      endpoint[0] += PADDING
      endpoint[1] += PADDING/4.0

      distance = root.distance
      unless distance.nil?
        depth = endpoint[0] + distance
      else
        depth = 418.0 - (root.level * JUMPLINE_INDENT) #todo:replace literal
      end

      @pdf.stroke = (0...3).map { 0 } # set the rgb color
      @pdf.line(endpoint, [depth, endpoint[1]])
      @pdf.line([depth, endpoint[1]], [depth, startpoint[1]])
      @pdf.line([depth, startpoint[1]], startpoint)

      @pdf.left_arrowhead(startpoint[0], startpoint[1])
    end


    # draw a path
    # documentation see raphaeljs
    # todo: fully support absolute and relative commands
    def draw_path(root)
      lines = []
      scale = [1, 1]
      start = []
      style = root.filled? ? :FD : ""
      @pdf.fill = (1..3).map { root.filled? ? 0 : 255 }

      root.path.each do |element|
        case element.first
          when "M"
            @pdf.lines(lines, start.first, start.last, scale, style, false) unless lines.empty?
            lines = []
            start = element[1 .. 2]
          when "L"
            @pdf.lines(lines, start.first, start.last, scale, style, false) unless lines.empty?
            lines = []
            start = element[1 .. 2]
          when "l"
            lines.push element[1 .. -1]
          when "c"
            lines.push element[1 .. -1]
          when "z"
            @pdf.lines(lines, start.first, start.last, scale, "FD", true) unless lines.empty?
            lines = []
          else
            $log.error("BUG: unsupported command '#{element.first}' in glyph (#{__FILE__} #{__LINE__})")
        end
      end
      @pdf.lines(lines, start.first, start.last, scale, style, false) unless lines.empty?
    end
  end

end