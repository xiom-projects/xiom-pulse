// XIOM PULSE -- dynamic multi-page site scaffold (Beacon tier).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small server-rendered site that exercises the dynamic site surface:
//   * a shared layout + nav/footer partials composed with xiom.template
//     0.2.0 (sections, loops, inverted sections, auto-escaping),
//   * application/x-www-form-urlencoded contact form parsing and validation
//     with xiom.pulse.urlenc,
//   * static assets served through the Beacon fallback hook via xiom.static
//     (same traversal guard and validators as the Station site mode),
//   * a custom 404 page.
//
// This is an example, not the product server: it keeps template reads per
// request for clarity. A production site should cache the compiled template
// strings at startup (the package has no compile step, so caching the Str is
// enough).
//
// Build: scripts\build.ps1 examples\site\main.xi -Name site_example
// Run:   PULSE_PORT=8080 out\site_example.exe   (from the repo root)
//        SITE_ROOT defaults to "examples/site"; set it when running elsewhere.

module site_example

use xiom.pulse.app;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.pulse.urlenc;
use xiom.template.blocks;
use xiom.static;
use xiom.io;
use xiom.string;
use xiom.env;

/// site_root is the directory that holds templates/ and public/. It is
/// resolved per request so a test can point the scaffold at a fixture.
/// Complexity: O(1).
fn site_root() -> Str {
  return env.var_or("SITE_ROOT", "examples/site");
}

/// read_text loads one UTF-8 text file under the site root; a missing file
/// is logged and renders as empty text (the caller still returns a valid
/// response, and the smoke fails on the missing marker). Complexity: O(file).
fn read_text(rel: Str) -> Str {
  let path = io.join_paths(site_root(), rel);
  let r = io.read_file(path);
  if r.is_ok {
    return r.value;
  }
  io.println("site: cannot read " + path);
  return "";
}

/// render renders one template file with `data`, auto-escaping every
/// interpolation. A template error is logged and renders empty so a broken
/// page cannot leak a partial document. Complexity: O(template + data).
fn render(tmpl_path: Str, data: &TemplateData) -> Str {
  let tmpl = read_text(tmpl_path);
  if tmpl.len() == 0 {
    return "";
  }
  let r = template_render_blocks(tmpl, data, true);
  if r.is_ok {
    return r.value;
  }
  io.println("site: template error in " + tmpl_path + ": " + r.error);
  return "";
}

/// render_page composes one page: render the page body, then inject the
/// body plus the shared nav/footer partials into the layout as raw
/// fragments. Partials are rendered with empty data because they are
/// static; the layout's title and raw slots are the only layout inputs.
/// Complexity: O(page + layout).
fn render_page(page: Str, title: Str, data: &TemplateData) -> Str {
  let body = render("templates/pages/" + page, data);
  var empty = template_data_new();
  let nav = render("templates/partials/nav.html", &empty);
  let footer = render("templates/partials/footer.html", &empty);
  var page_data = template_data_new();
  template_data_set_str(&mut page_data, "title", title);
  template_data_set_str(&mut page_data, "nav", nav);
  template_data_set_str(&mut page_data, "footer", footer);
  template_data_set_str(&mut page_data, "content", body);
  return render("templates/layout.html", &page_data);
}

/// page_out wraps a rendered page in a text/html response.
/// Complexity: O(1).
fn page_out(status: Int, page: Str, title: Str, data: &TemplateData) -> HandlerOut {
  return app.out_html(status, render_page(page, title, data));
}

/// home renders the landing page. Complexity: O(page).
fn home() -> HandlerOut {
  var d = template_data_new();
  template_data_set_str(&mut d, "site_name", "PULSE site example");
  template_data_set_str(&mut d, "tagline", "A dynamic multi-page site on the PULSE Beacon core.");
  return page_out(200, "index.html", "Home", &d);
}

/// about renders the about page. Complexity: O(page).
fn about() -> HandlerOut {
  var d = template_data_new();
  template_data_set_str(&mut d, "site_name", "PULSE site example");
  return page_out(200, "about.html", "About", &d);
}

/// features renders the feature list from a Vec[Str] section.
/// Complexity: O(page + items).
fn features() -> HandlerOut {
  var items: Vec[Str] = Vec[Str].new();
  items.push("Shared layout and partial composition");
  items.push("Loops, conditionals and dotted paths");
  items.push("HTML auto-escaping on every interpolation");
  items.push("application/x-www-form-urlencoded form parsing");
  items.push("Static assets with ETag and traversal protection");
  items.push("A custom 404 rendered by the same layout");
  var d = template_data_new();
  template_data_set_str(&mut d, "site_name", "PULSE site example");
  template_data_set_list(&mut d, "features", &items);
  return page_out(200, "features.html", "Features", &d);
}

/// contact_page renders the contact form with an optional error and the
/// values the user already typed. Every value is auto-escaped.
/// Complexity: O(page).
fn contact_page(status: Int, error: Str, name: Str, message: Str) -> HandlerOut {
  var d = template_data_new();
  template_data_set_str(&mut d, "error", error);
  template_data_set_str(&mut d, "name", name);
  template_data_set_str(&mut d, "message", message);
  return page_out(status, "contact.html", "Contact", &d);
}

/// contact_post validates and reflects one submitted form. A non-form
/// Content-Type is 415; validation failures re-render the form with 400;
/// success renders the thank-you page. Complexity: O(body + page).
fn contact_post(req: &PulseRequest, body: Str) -> HandlerOut {
  if !urlenc.form_is_urlencoded(http.header_get(req, "content-type")) {
    return contact_page(415, "Send this form as application/x-www-form-urlencoded.", "", "");
  }
  let f = urlenc.parse_form(body);
  let name = string.str_trim(urlenc.form_value(&f.0, &f.1, "name"));
  let message = string.str_trim(urlenc.form_value(&f.0, &f.1, "message"));
  var err: Str = "";
  if name.len() == 0 {
    err = "Name is required.";
  } elif name.len() > 64 {
    err = "Name is too long (64 bytes max).";
  } elif message.len() == 0 {
    err = "Message is required.";
  } elif message.len() > 2000 {
    err = "Message is too long (2000 bytes max).";
  }
  if err.len() > 0 {
    return contact_page(400, err, name, message);
  }
  var d = template_data_new();
  template_data_set_str(&mut d, "name", name);
  template_data_set_str(&mut d, "message", message);
  return page_out(200, "thanks.html", "Thanks", &d);
}

/// not_found renders the custom 404 page with the requested path escaped by
/// the template. Complexity: O(page).
fn not_found(path: Str) -> HandlerOut {
  var d = template_data_new();
  template_data_set_str(&mut d, "path", path);
  return page_out(404, "404.html", "Not found", &d);
}

/// path_of strips the query string from a request target. Complexity: O(n).
fn path_of(target: Str) -> Str {
  let qo = string.str_index_of(target, "?");
  if qo.is_none {
    return target;
  }
  return string.str_slice(target, 0, qo.value);
}

/// site_fallback serves /assets/<path> from public/ with xiom.static and
/// renders the custom 404 for everything else. It is installed as the
/// Beacon fallback hook, so registered API routes keep precedence.
/// Complexity: O(file) for an asset, O(page) for a miss.
fn site_fallback(req: &PulseRequest, _body: Str) -> HandlerOut {
  let m = req.method;
  if m == "GET" || m == "HEAD" {
    let path = path_of(req.target);
    if string.str_starts_with(path, "/assets/") {
      let rel = string.str_slice(path, 8, path.len());
      let pol = StaticPolicy{ max_age: 3600; immutable: false; must_revalidate: false; no_store: false; };
      let sr = static.static_serve(io.join_paths(site_root(), "public"), rel, http.header_get(req, "if-none-match"), http.header_get(req, "range"), m == "HEAD", &pol);
      if sr.status != 404 {
        var ct: Str = "application/octet-stream";
        var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
        var hi: Int = 0;
        while hi < sr.headers.len() {
          let h = sr.headers[hi];
          if h.name == "Content-Type" {
            ct = h.value;
          } elif h.name != "Content-Length" {
            // Framing is owned by the response builder; copying the static
            // engine's Content-Length would emit it twice.
            hs.push((h.name, h.value));
          }
          hi = hi + 1;
        }
        return HandlerOut{ status: sr.status; content_type: ct; headers: hs; body: ""; body_bytes: sr.body };
      }
    }
    return not_found(path);
  }
  return not_found(req.target);
}

/// handle dispatches the registered site routes. Complexity: O(dispatch).
fn handle(req: &PulseRequest, m: &PulseRoute, body: Str) -> HandlerOut {
  if m.route_id == 1 { return home(); }
  if m.route_id == 2 { return about(); }
  if m.route_id == 3 { return features(); }
  if m.route_id == 4 { return contact_page(200, "", "", ""); }
  if m.route_id == 5 { return contact_post(req, body); }
  if m.route_id == 6 {
    return app.out_json(200, "{\"status\":\"ok\",\"site\":\"example\"}");
  }
  return not_found(req.target);
}

pub fn main() -> Int {
  let _ = app.register("GET", "/");
  let _ = app.register("GET", "/about");
  let _ = app.register("GET", "/features");
  let _ = app.register("GET", "/contact");
  let _ = app.register("POST", "/contact");
  let _ = app.register("GET", "/health");
  var hooks = app.hooks_new();
  let _ = app.hooks_install_fallback(&mut hooks, site_fallback);
  return app.serve_with(handle, &hooks);
}
