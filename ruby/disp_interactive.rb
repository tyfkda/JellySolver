#! /usr/bin/env ruby

require_relative 'jelly/jelly'
require_relative 'jelly/stage'

# "▀　▄　█　▖▗　▘▙　▚　▐　▛　▜　▝　▞　▟　▌■　▘"
Boxes = [
    ['▐████▌', '▐████▌'],
    ['▗▄▄▄▄▖', '▐████▌', '▝▀▀▀▀▘'],
]

def rgb(r, g, b)
    return r * 36 + g * 6 + b + 16
end

Black  = 232
Red    = rgb(5, 0, 0)
Green  = rgb(0, 5, 0)
Blue   = rgb(0, 0, 5)
Yellow = rgb(5, 5, 0)

SkyColor = rgb(0, 4, 4)
BlackBlockColor = { fg: Black, bg: SkyColor }

ColorTable = {
    R: { fg: Red, bg: SkyColor },
    G: { fg: Green, bg: SkyColor },
    B: { fg: Blue, bg: SkyColor },
    Y: { fg: Yellow, bg: SkyColor },
    "@": BlackBlockColor,
    "*": BlackBlockColor,
    "$": BlackBlockColor,
    "%": BlackBlockColor,
}

ResetColor = "\033[0m"
ResetFg = "\033[39m"
ResetBg = "\033[49m"
ClearScreen = "\033[2J\033[H"

def set_fg(fg)
    return "\033[38;5;#{fg}m"
end

def set_bg(bg)
    return "\033[48;5;#{bg}m"
end

def disp_stage_color(stage)
    print(ClearScreen)
    lines = stage.make_lines()
    lines.each_with_index do |line, i|
        box = Boxes[i & 1]
        arrs = Array.new(box.size) { Array.new }
        line.each_char do |c|
            fg = bg = nil
            case c
            when '#'
                fg = rgb(1, 0, 0)
                bg = SkyColor
            when '.'
                ;
            else
                t = ColorTable[c.upcase.to_sym]
                fg = t[:fg]
                bg = t[:bg]
            end
            if !fg && !bg
                box.each_with_index do |s, j|
                    arrs[j] << ("#{ResetFg}#{set_bg(SkyColor)}" + ' ' * s.size)
                end
                next
            end
            box.each_with_index do |s, j|
                arrs[j] << "#{fg ?set_fg(fg):ResetFg}#{bg ?set_bg(bg):ResetBg}#{s}"
            end
        end
        arrs.each do |s|
            puts "#{s.join('')}#{ResetColor}"
        end
    end
end

def disp_solution_interactive(stage, moves)
    disp_stage_color(stage)
    moves.each_with_index do |move, step|
        print "Step #{step + 1} :(#{move[0]}, #{move[1]}), #{%w(<- ->)[(move[2]+1)>>1]} $ "
        $stdin.gets
        jelly = stage.jellies.find {|it| it.occupy_position?(move[0], move[1])}
        stage = Jelly::Solver.move_jelly(stage, jelly, move[2])
        raise "Invalid move: #{move}" if stage.nil?
        disp_stage_color(stage)
    end
end
