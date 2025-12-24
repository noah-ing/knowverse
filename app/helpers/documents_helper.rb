module DocumentsHelper
  def file_type_bg_class(file_type)
    case file_type&.downcase
    when 'pdf' then 'bg-red-100'
    when 'doc', 'docx' then 'bg-blue-100'
    when 'xls', 'xlsx' then 'bg-green-100'
    when 'txt' then 'bg-gray-100'
    when 'md' then 'bg-gray-100'
    else 'bg-gray-100'
    end
  end

  def file_type_text_class(file_type)
    case file_type&.downcase
    when 'pdf' then 'text-red-600'
    when 'doc', 'docx' then 'text-blue-600'
    when 'xls', 'xlsx' then 'text-green-600'
    when 'txt' then 'text-gray-600'
    when 'md' then 'text-gray-600'
    else 'text-gray-600'
    end
  end
end
