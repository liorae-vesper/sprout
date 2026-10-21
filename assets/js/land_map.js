import L from "leaflet"

export default {
  mounted() {
    this.kind = "plot"
    this.points = []
    this.drawing = false
    this.canvas = this.el.querySelector(".land-map-canvas")
    this.status = this.el.querySelector(".map-status")
    this.map = L.map(this.canvas, {scrollWheelZoom: false}).setView([-23.544, -46.63], 14)
    this.tiles = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(this.map)
    this.tiles.on("tileerror", () => {
      if (!this.drawing) this.status.textContent = "Basemap unavailable. Saved boundaries and drawing still work."
    })
    this.regions = L.featureGroup().addTo(this.map)
    this.parcels = L.featureGroup().addTo(this.map)
    this.handleEvent("land-saved", ({kind}) => { if (kind === this.kind) this.clearDraft() })
    this.draft = L.layerGroup().addTo(this.map)
    this.el.querySelector('[data-action="draw"]').onclick = () => this.startDrawing("plot")
    this.el.querySelector('[data-action="parcel"]').onclick = () => this.startDrawing("parcel")
    this.el.querySelector('[data-action="undo"]').onclick = () => {
      this.points.pop()
      this.paintDraft()
    }
    this.el.querySelector('[data-action="clear"]').onclick = () => this.clearDraft()
    this.el.querySelector('[data-action="finish"]').onclick = () => {
      this.drawing = false
      this.canvas.classList.remove("drawing")
      this.writeBoundary()
      const details = document.querySelector(this.kind === "parcel" ? ".parcel-intake" : ".field-intake")
      details.open = true
      details.scrollIntoView({behavior: "smooth", block: "center"})
      details.querySelector('input[type="text"]').focus({preventScroll: true})
      this.status.textContent = "Boundary ready. Choose the containing parcel for a plot, enter a name and hectares, then save."
    }
    this.el.querySelector('[data-action="fit"]').onclick = () => this.fitLand()
    this.map.on("click", event => {
      if (!this.drawing) return
      this.points.push([Number(event.latlng.lat.toFixed(7)), Number(event.latlng.lng.toFixed(7))])
      this.paintDraft()
    })
    this.renderRegions()
    this.fitLand()
    this.resize = new ResizeObserver(() => this.map.invalidateSize())
    this.resize.observe(this.canvas)
  },
  updated() {
    this.renderRegions()
    if (this.points.length) this.writeBoundary()
  },
  startDrawing(kind) {
    if (kind !== this.kind) this.clearDraft()
    this.kind = kind
    this.drawing = true
    this.canvas.classList.add("drawing")
    this.paintDraft()
  },
  renderRegions() {
    const fields = JSON.parse(this.el.dataset.fields)
    this.parcels.clearLayers()
    JSON.parse(this.el.dataset.parcels).forEach(parcel => {
      const polygon = L.polygon(parcel.boundary.points, {color: "#9b7952", weight: 3, dashArray: "8 6", fillOpacity: 0, interactive: false}).addTo(this.parcels)
      const label = document.createElement("span")
      label.textContent = `${parcel.name} · land parcel`
      polygon.bindTooltip(label)
    })
    this.regions.clearLayers()
    fields.forEach(field => {
      const selected = String(field.id) === this.el.dataset.selected
      const polygon = L.polygon(field.boundary.points, {
        color: selected ? "#496b3f" : "#8a9f65", weight: selected ? 4 : 2,
        fillColor: selected ? "#a8c484" : "#c5d6a3", fillOpacity: 0.45,
        bubblingMouseEvents: false,
      }).addTo(this.regions)
      const label = document.createElement("span")
      label.textContent = `${field.name} · ${field.area_ha} ha`
      polygon.bindTooltip(label)
      polygon.on("click", event => {
        if (this.drawing) {
          this.points.push([event.latlng.lat, event.latlng.lng])
          this.paintDraft()
        } else this.pushEvent("select", {id: String(field.id)})
      })
    })
  },
  fitLand() {
    const bounds = L.featureGroup([...this.parcels.getLayers(), ...this.regions.getLayers()]).getBounds()
    if (bounds.isValid()) this.map.fitBounds(bounds, {padding: [35, 35], maxZoom: 16})
  },
  paintDraft() {
    this.draft.clearLayers()
    if (this.points.length > 1) L.polygon(this.points, {color: "#bb8b48", dashArray: "6 5", interactive: false}).addTo(this.draft)
    this.points.forEach(point => L.circleMarker(point, {radius: 5, color: "#94692f", fillOpacity: 1, interactive: false}).addTo(this.draft))
    this.el.querySelector('[data-action="undo"]').disabled = this.points.length === 0
    this.el.querySelector('[data-action="clear"]').disabled = !this.drawing && this.points.length === 0
    this.el.querySelector('[data-action="finish"]').disabled = this.points.length < 3
    this.writeBoundary()
    this.status.textContent = `${this.points.length} GPS vertices. Click around the edge in order; use at least three points. Avoid crossing lines.`
  },
  writeBoundary() {
    const input = document.querySelector(this.kind === "parcel" ? '#parcel-form textarea' : '#field-form textarea')
    input.value = JSON.stringify(this.points)
    input.dispatchEvent(new Event("input", {bubbles: true}))
  },
  clearDraft() {
    this.points = []
    this.drawing = false
    this.canvas.classList.remove("drawing")
    this.paintDraft()
    this.writeBoundary()
    this.status.textContent = "Draft cleared. Your saved regions are unchanged."
  },
  destroyed() {
    this.resize.disconnect()
    this.map.remove()
  },
}
