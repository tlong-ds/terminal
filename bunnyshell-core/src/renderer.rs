use std::sync::{Arc, Mutex};
use crate::BunError;
use raw_window_handle::{
    RawWindowHandle, AppKitWindowHandle, RawDisplayHandle, AppKitDisplayHandle,
    HasWindowHandle, HasDisplayHandle, WindowHandle, DisplayHandle, HandleError
};

struct RawWindow {
    nsview: *mut std::ffi::c_void,
}

// Implement Send + Sync so it can be held inside async contexts/UniFFI objects safely
unsafe impl Send for RawWindow {}
unsafe impl Sync for RawWindow {}

impl HasWindowHandle for RawWindow {
    fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
        let handle = AppKitWindowHandle::new(
            std::ptr::NonNull::new(self.nsview).ok_or(HandleError::NotSupported)?
        );
        unsafe { Ok(WindowHandle::borrow_raw(RawWindowHandle::AppKit(handle))) }
    }
}

impl HasDisplayHandle for RawWindow {
    fn display_handle(&self) -> Result<DisplayHandle<'_>, HandleError> {
        let handle = AppKitDisplayHandle::new();
        unsafe { Ok(DisplayHandle::borrow_raw(RawDisplayHandle::AppKit(handle))) }
    }
}

#[derive(uniffi::Object)]
pub struct TerminalRenderer {
    device: wgpu::Device,
    queue: wgpu::Queue,
    surface: wgpu::Surface<'static>,
    surface_config: Mutex<wgpu::SurfaceConfiguration>,
    font_system: Mutex<glyphon::FontSystem>,
    atlas: Mutex<glyphon::TextAtlas>,
    text_renderer: Mutex<glyphon::TextRenderer>,
    #[allow(dead_code)]
    cache: glyphon::Cache,
    swash_cache: Mutex<glyphon::SwashCache>,
    viewport: Mutex<glyphon::Viewport>,
    width: Mutex<u32>,
    height: Mutex<u32>,
}

#[uniffi::export]
impl TerminalRenderer {
    #[uniffi::constructor]
    pub fn new(nsview_ptr: u64, width: u32, height: u32) -> Result<Arc<Self>, BunError> {
        let window = RawWindow {
            nsview: nsview_ptr as *mut std::ffi::c_void,
        };

        // Create wgpu instance targeting Metal
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::METAL,
            ..Default::default()
        });

        // Surface must be 'static, which works because we wrap RawWindow in wgpu's surface creator
        let surface = unsafe {
            // Transmute the lifetime of the surface created from RawWindow
            // since RawWindow is owned by this function, but the view pointer is long-lived on macOS side.
            let surface = instance.create_surface(&window).map_err(|e| e.to_string())?;
            std::mem::transmute::<wgpu::Surface<'_>, wgpu::Surface<'static>>(surface)
        };

        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: Some(&surface),
            force_fallback_adapter: false,
        }))
        .ok_or_else(|| "Failed to find a suitable GPU adapter".to_string())?;

        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: Some("bunnyshell-gpu-device"),
                required_features: wgpu::Features::empty(),
                required_limits: wgpu::Limits::default(),
                memory_hints: Default::default(),
            },
            None,
        ))
        .map_err(|e| e.to_string())?;

        let surface_caps = surface.get_capabilities(&adapter);
        let surface_format = surface_caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(surface_caps.formats[0]);

        let w = width.max(1);
        let h = height.max(1);
        let surface_config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: surface_format,
            width: w,
            height: h,
            present_mode: wgpu::PresentMode::Fifo,
            desired_maximum_frame_latency: 2,
            alpha_mode: surface_caps.alpha_modes[0],
            view_formats: vec![],
        };
        surface.configure(&device, &surface_config);

        // Setup glyphon text rendering stack
        let cache = glyphon::Cache::new(&device);
        let font_system = glyphon::FontSystem::new();
        let mut atlas = glyphon::TextAtlas::new(&device, &queue, &cache, surface_format);
        let swash_cache = glyphon::SwashCache::new();
        let text_renderer = glyphon::TextRenderer::new(&mut atlas, &device, wgpu::MultisampleState::default(), None);
        let viewport = glyphon::Viewport::new(&device, &cache);

        Ok(Arc::new(Self {
            device,
            queue,
            surface,
            surface_config: Mutex::new(surface_config),
            font_system: Mutex::new(font_system),
            atlas: Mutex::new(atlas),
            text_renderer: Mutex::new(text_renderer),
            cache,
            swash_cache: Mutex::new(swash_cache),
            viewport: Mutex::new(viewport),
            width: Mutex::new(w),
            height: Mutex::new(h),
        }))
    }

    pub fn resize(&self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        let mut config = self.surface_config.lock().unwrap();
        config.width = width;
        config.height = height;
        self.surface.configure(&self.device, &config);
        *self.width.lock().unwrap() = width;
        *self.height.lock().unwrap() = height;
    }

    pub fn render(&self, lines: Vec<String>) -> Result<(), BunError> {
        let output = self.surface.get_current_texture().map_err(|e| e.to_string())?;
        let view = output.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("bunnyshell-render-encoder"),
        });

        let mut font_system = self.font_system.lock().unwrap();
        let mut atlas = self.atlas.lock().unwrap();
        let mut text_renderer = self.text_renderer.lock().unwrap();
        let mut swash_cache = self.swash_cache.lock().unwrap();
        let mut viewport = self.viewport.lock().unwrap();

        let w = *self.width.lock().unwrap();
        let h = *self.height.lock().unwrap();
        if w == 0 || h == 0 {
            return Ok(());
        }
        viewport.update(&self.queue, glyphon::Resolution { width: w, height: h });

        // Compile all lines into a cosmic-text buffer
        let mut buffer = cosmic_text::Buffer::new(&mut font_system, cosmic_text::Metrics::new(14.0, 18.0));
        buffer.set_size(&mut font_system, Some(w as f32), Some(h as f32));
        
        let text_content = lines.join("\n");
        buffer.set_text(&mut font_system, &text_content, cosmic_text::Attrs::new().color(cosmic_text::Color::rgb(240, 240, 240)), cosmic_text::Shaping::Advanced);
        buffer.shape_until_scroll(&mut font_system, true);

        text_renderer
            .prepare(
                &self.device,
                &self.queue,
                &mut font_system,
                &mut atlas,
                &viewport,
                [glyphon::TextArea {
                    buffer: &buffer,
                    left: 10.0,
                    top: 10.0,
                    scale: 1.0,
                    bounds: glyphon::TextBounds {
                        left: 0,
                        top: 0,
                        right: w as i32,
                        bottom: h as i32,
                    },
                    default_color: cosmic_text::Color::rgb(240, 240, 240),
                    custom_glyphs: &[],
                }],
                &mut swash_cache,
            )
            .map_err(|e| format!("Glyphon prepare error: {:?}", e))?;

        {
            let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("bunnyshell-render-pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: 0.05,
                            g: 0.05,
                            b: 0.05,
                            a: 1.0,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });

            text_renderer.render(&atlas, &viewport, &mut rpass).unwrap();
        }

        self.queue.submit(Some(encoder.finish()));
        output.present();

        atlas.trim();

        Ok(())
    }
}

