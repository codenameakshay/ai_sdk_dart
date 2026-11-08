/// One minimal OpenUI Lang program per component, keyed by its type name.
///
/// Each program renders the component on its own inside a Col, or inside the
/// parent it needs (ListItem in List, MapMarker in Map, shapes in Svg).
const Map<String, String> goldenPrograms = {
  'Col': 'root = Col([Text("First line"), Text("Second line")], 8)',
  'Row': 'root = Row([Text("Left"), Text("Right")], 8)',
  'Box': 'root = Col([Box([Text("Inside a box")], "row", 8, 12)])',
  'Grid':
      'root = Grid([Text("A"), Text("B"), Text("C"), Text("D")], 2, 160, 8)',
  'Card': 'root = Card([Text("Inside a card")])',
  'Carousel':
      'root = Carousel([Text("One"), Text("Two"), Text("Three")], 160, 8)',
  'Popover': 'root = Col([Popover("Show source", "Source: encyclopedia")])',
  'Divider': 'root = Col([Text("Above"), Divider(), Text("Below")])',
  'Spacer': 'root = Row([Text("Start"), Spacer(), Text("End")])',
  'Title': 'root = Col([Title("A heading", "lg")])',
  'Text': 'root = Col([Text("Some body text.")])',
  'Caption': 'root = Col([Caption("Small secondary text")])',
  'Label': 'root = Col([Label("Field label")])',
  'Badge': 'root = Row([Badge("New", "success", "star")])',
  'Link': 'root = Col([Link("Documentation", "https://example.com")])',
  'List':
      'root = Col([List(["Bread", ListItem("Milk", "Two litres")], "bullet")])',
  'ListItem':
      'root = Col([List([ListItem("Morning", "Coffee", "09:00"), ListItem("Noon", "Lunch", "12:00")], "none", true)])',
  'Markdown': 'root = Col([Markdown("**Bold**, *italic* and `code`.")])',
  'Quote':
      'root = Col([Quote("Simplicity is the ultimate sophistication.", "Leonardo da Vinci")])',
  'Code': 'root = Col([Code("x = 1 + 2", "dart")])',
  'Math': 'root = Col([Math("E = mc^2")])',
  'Button': 'root = Col([Button("Continue")])',
  'IconButton': 'root = Row([IconButton("plus", null, "Add")])',
  'Pressable':
      'root = Col([Pressable([Text("Tap this tile")], null, true, 12)])',
  'Input':
      'root = Col([Input(\$name, "Name", "text", "Your name")])\n\$name = ""',
  'TextArea':
      'root = Col([TextArea(\$notes, "Notes", "Write here", 3)])\n\$notes = ""',
  'Select':
      'root = Col([Select(\$pick, ["Red", "Green", "Blue"], "Colour", "Choose")])\n\$pick = ""',
  'SegmentedControl':
      'root = Col([SegmentedControl(\$view, ["Day", "Week", "Month"], true)])\n\$view = "Day"',
  'Slider':
      'root = Col([Slider(\$volume, 0, 100, 1, "Volume", "%")])\n\$volume = 40',
  'Checkbox':
      'root = Col([Checkbox(\$done, "Buy milk", true)])\n\$done = false',
  'RadioGroup':
      'root = Col([RadioGroup(\$plan, ["Free", "Pro"], "Plan", "pills")])\n\$plan = "Free"',
  'DatePicker':
      'root = Col([DatePicker(\$day, "Start date")])\n\$day = "2030-05-17"',
  'Timer': 'root = Col([Timer(\$left, "Time left")])\n\$left = 90',
  'Form':
      'root = Col([Form([Input(\$name, "Name"), Button("Save")])])\n\$name = ""',
  'SearchImage': 'root = Col([SearchImage("Belém Tower Lisbon", 1.6, "md")])',
  'Image':
      'root = Col([Image("https://example.com/photo.jpg", "A photo", 1.6, "md")])',
  'Icon': 'root = Row([Icon("map-pin", "lg")])',
  'Table': 'root = Col([Table(["Name", "Qty"], [["Apple", 3], ["Pear", 2]])])',
  'Chart':
      'root = Col([Chart("bar", [{month: "Jan", sales: 12}, {month: "Feb", sales: 18}], "month")])',
  'Map':
      'root = Col([Map([MapMarker("Berlin", 52.52, 13.405), MapMarker("Potsdam", 52.39, 13.06)], true, null, 240)])',
  'MapMarker':
      'root = Col([Map([MapMarker("Berlin", 52.52, 13.405, "city")], false, null, 240)])',
  'YouTube': 'root = Col([YouTube("dQw4w9WgXcQ", "Demo video")])',
  'Flashcard': 'root = Col([Flashcard("Bonjour", "Hello", "Tap to flip")])',
  'Celebration': 'root = Col([Text("Done"), Celebration(true)])',
  'Svg': 'root = Col([Svg([Circle(60, 40, 30, "#2563eb")], "0 0 120 80")])',
  'Circle':
      'root = Col([Svg([Circle(60, 40, 30, "#2563eb", "#1e3a8a", 3)], "0 0 120 80")])',
  'Ellipse':
      'root = Col([Svg([Ellipse(60, 40, 45, 25, "#16a34a")], "0 0 120 80")])',
  'Rect':
      'root = Col([Svg([Rect(10, 10, 100, 60, "#fde68a", "#b45309", 2, 1, 8)], "0 0 120 80")])',
  'Line':
      'root = Col([Svg([Line(10, 70, 110, 10, "#334155", 3)], "0 0 120 80")])',
  'Path':
      'root = Col([Svg([Path("M10 70 Q60 0 110 70", "none", "#7c3aed", 3)], "0 0 120 80")])',
  'Polyline':
      'root = Col([Svg([Polyline("10,70 40,30 70,50 110,10", "#0891b2", 3)], "0 0 120 80")])',
  'Polygon':
      'root = Col([Svg([Polygon("10,70 60,10 110,70", "#f59e0b", "#92400e", 2)], "0 0 120 80")])',
  'G':
      'root = Col([Svg([G([Circle(30, 40, 16, "#16a34a"), Circle(90, 40, 16, "#dc2626")], "translate(0 0)")], "0 0 120 80")])',
  'SvgText':
      'root = Col([Svg([SvgText("Hello", 60, 44, 14, "#111827", "middle", "semibold")], "0 0 120 80")])',
  'HtmlView': 'root = Col([HtmlView("<p>Hello from HTML</p>", 120, "Demo")])',
};
