require "./model"
require "./events"

# Applies a CanvasEvent to the model in-place and returns the model.
#
# Design rules:
#   - Only this function is allowed to mutate model.elements.
#   - apply() is idempotent given the same model state and event.
#   - Missing element IDs are silently ignored (safe for stale replay).
def apply(model : CanvasModel, event : CanvasEvent) : CanvasModel
  case event
  when CreateRectEvent
    model.elements << RectModel.new(
      event.id, event.bounds,
      event.fill, event.stroke, event.stroke_width, event.label
    )
  when CreateTextEvent
    model.elements << TextModel.new(
      event.id, event.bounds, event.text, event.fixed_width, event.max_auto_width
    )
  when CreateArrowEvent
    # Only create when both endpoints still exist — guards against stale replay
    # after one endpoint was deleted before this event is re-applied.
    if model.find_by_id(event.from_id) && model.find_by_id(event.to_id)
      model.elements << ArrowModel.new(
        event.id, event.from_id, event.to_id, event.routing_style
      )
    end
  when DeleteElementEvent
    model.elements.reject! { |e| e.id == event.id }
    # Cascade: any arrow that referenced the deleted element becomes dangling.
    model.elements.reject! do |e|
      e.is_a?(ArrowModel) && (e.from_id == event.id || e.to_id == event.id)
    end
  when MoveElementEvent
    model.find_by_id(event.id).try { |e| e.bounds = event.new_bounds }
  when MoveMultiEvent
    event.moves.each do |(id, new_bounds)|
      model.find_by_id(id).try { |e| e.bounds = new_bounds }
    end
  when ResizeElementEvent
    model.find_by_id(event.id).try do |e|
      e.bounds = event.new_bounds
      # Resizing a text element locks its width so it no longer auto-grows.
      if e.is_a?(TextModel)
        e.fixed_width = true
      end
    end
  when TextChangedEvent
    model.find_by_id(event.id).try do |e|
      e.bounds = event.new_bounds
      case e
      when TextModel then e.text = event.new_text
      when RectModel then e.label = event.new_text
      end
    end
  when ChangeRectColorEvent
    model.find_by_id(event.id).try do |e|
      if e.is_a?(RectModel)
        e.fill = event.fill
        e.stroke = event.stroke
        e.label_color = event.label_color
      end
    end
  when ArrowRoutingChangedEvent
    model.find_by_id(event.id).try do |e|
      if e.is_a?(ArrowModel)
        e.routing_style = event.new_style
      end
    end
  when InsertTextEvent
    model.find_by_id(event.id).try do |e|
      case e
      when TextModel
        chars = e.text.chars
        e.text = (chars[0, event.position] + event.text.chars + chars[event.position..]).join
        e.bounds = event.new_bounds
      when RectModel
        chars = e.label.chars
        e.label = (chars[0, event.position] + event.text.chars + chars[event.position..]).join
        e.bounds = event.new_bounds
      end
    end
  when DeleteTextEvent
    model.find_by_id(event.id).try do |e|
      case e
      when TextModel
        chars = e.text.chars
        e.text = (chars[0, event.start] + chars[(event.start + event.length)..]).join
        e.bounds = event.new_bounds
      when RectModel
        chars = e.label.chars
        e.label = (chars[0, event.start] + chars[(event.start + event.length)..]).join
        e.bounds = event.new_bounds
      end
    end
  end

  model
end
