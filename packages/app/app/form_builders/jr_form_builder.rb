# frozen_string_literal: true

class JrFormBuilder < ActionView::Helpers::FormBuilder
  def jr_text_field(method, label: nil, **options)
    field_wrapper(method, label: label) do
      @template.text_field(@object_name, method, objectify_options(options.merge(
        class: input_classes
      )))
    end
  end

  def jr_password_field(method, label: nil, **options)
    field_wrapper(method, label: label) do
      @template.password_field(@object_name, method, objectify_options(options.merge(
        class: input_classes
      )))
    end
  end

  private

  def field_wrapper(method, label: nil, &block)
    @template.content_tag(:div, class: "space-y-1") do
      label_html = label ? @template.content_tag(:label,
        label,
        for: "#{@object_name}_#{method}",
        class: "block text-sm font-medium text-slate-700 dark:text-slate-300") : "".html_safe
      label_html + @template.capture(&block)
    end
  end

  def input_classes
    "block w-full rounded-md border border-slate-300 px-3 py-2 text-sm shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
  end
end
