pub const Type = enum {
    Loop,
    PlayOnce,
    PlayOnceReset,
};

const Animation2D = @This();

current_frame: u32,
total_frames: u32,
current_time: f32,
frame_time: f32,
playing: bool,
animation_type: Type,

pub fn new(frames: u32, frame_time: f32, animation_type: Type) Animation2D {
    return .{ .current_frame = 0, .total_frames = frames, .current_time = 0.0, .frame_time = frame_time, .playing = false, .animation_type = animation_type };
}

pub fn currentFrame(self: Animation2D) u32 {
    return self.current_frame;
}

pub fn play(self: *Animation2D) void {
    self.playing = true;
}

pub fn reset(self: *Animation2D) void {
    self.current_frame = 0;
    self.current_time = 0;
}

pub fn update(self: *Animation2D, time: f32) void {
    if (!self.playing) return;
    self.current_time += time;
    if (self.current_time <= self.frame_time) return;

    self.current_time -= self.frame_time;
    if (self.current_frame < self.total_frames - 1) {
        self.current_frame += 1;
        return;
    }

    switch (self.animation_type) {
        Type.Loop => self.current_frame = 0,
        Type.PlayOnce => self.playing = false,
        Type.PlayOnceReset => {
            self.playing = false;
            self.current_frame = 0;
        },
    }
}
