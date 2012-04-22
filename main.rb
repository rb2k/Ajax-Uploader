#!/usr/bin/ruby
require 'webrick'
require 'stringio'
require 'cgi'
require 'digest/sha1'
include WEBrick


# This static class keeps track of the upload percentages
# and provides the mapping of UID's to file paths
class UploadStateMapping
	class << self; attr_accessor :progress, :file_path end
	@progress = Hash.new
	@file_path = Hash.new
end

# This servlet receives the chunks of the actual file uploads
# and updates the progress status in the UploadStateMapping accordingly
# The files are saved to a directory called "uploads" under their SHA1 hash
class FileUpload < HTTPServlet::AbstractServlet
	def do_POST(request, response)
		# make sure it's actually a form-data post
		unless request.content_type =~ /^multipart\/form-data; boundary=(.+)/
			raise HTTPStatus::BadRequest
		end
		# will be an array with a single string inside -> to_s
		uid = CGI.parse(request.query_string)['uid'].to_s
		raise HTTPStatus::BadRequest if uid.empty?
		# set our initial upload progress to 0 for the posted uid
		UploadStateMapping.progress[uid] = 0
		# this is the total length of content that is currently uploaded
		total_length = request.content_length.to_f
		# keep request chunks in a StringIO class, more efficient than a regular String
		chunk_buffer = StringIO.new
		# this will be triggered whenever we receive another chunk of data
		request.body do |chunk|
			buffer_position = chunk_buffer.pos.to_i
			progress = ((buffer_position / total_length) * 100).to_i
			UploadStateMapping.progress[uid] = progress
			chunk_buffer << chunk
		end
		# no that we're done, let's save the whole thing to a variable
		body = chunk_buffer.string
		# parse form data from the in the post request
		form_data = extract_form_data_from_request(request['content-type'], body)
		raise HTTPStatus::BadRequest unless form_data.key?('file-input')
		# get the name of the file being uploaded from the posted formdata
		filename = body.match(/filename="(.*)"/)[1]
		file_ext = File.extname(filename)
		body_hash = Digest::SHA1.hexdigest(form_data['file-input'])
		# this helps us keep duplicates away while preserving at least the extension
		# it also gets rid of strange filenames
		upload_path = "uploads/#{body_hash}#{file_ext}"
		unless File.exist?(upload_path)
			File.open(upload_path, 'wb') {|f| f.write(form_data['file-input']) }
		end
		# keep track of where we actually saved the file to. This will be shown to the user.
		UploadStateMapping.file_path[uid] = upload_path
		# Now that we're done, we can manually set the progress to 100%
		UploadStateMapping.progress[uid] = 100
		# respond upload complete
		response.status = 200
		response['Content-Type'] = "text/plain"
		response.body = 'upload complete'
	end

	# figures out where the form data begins, extracts it
	# and returns a hash with the form data
	def extract_form_data_from_request(content_type, post_body)
		boundary = content_type.match(/^multipart\/form-data; boundary=(.+)/)[1]
		boundary = HTTPUtils::dequote(boundary)
		HTTPUtils::parse_form_data(post_body, boundary)
	end
end

# This is the ajax endpoint that returns the
# upload percentage to the user's browser
class FileUploadProgress < HTTPServlet::AbstractServlet
	def do_GET(request, response)
		params = CGI.parse(request.query_string)
		# will be an array with a single string inside -> to_s
		uid = params['uid'].to_s
		# make sure we have a uid
		raise HTTPStatus::BadRequest if uid.empty?
		# create progress response json object
		progress = "{\"progress\": \"#{UploadStateMapping.progress[uid].to_i}\"}"
		response.status = 200
		response['Content-Type'] = "application/json"
		response.body = progress
	end
end

########################################
# This request takes a UID and 
# returns the path of the matching uploaded file
class FileUploadPath < HTTPServlet::AbstractServlet
	def do_GET(request, response)
		# will be an array with a single string inside -> to_s
		uid = request.query['uid'].to_s
		raise HTTPStatus::BadRequest if uid.empty?
		# our json response with the relative path for the upload
		matching_path = UploadStateMapping.file_path[uid]
		raise HTTPStatus::BadRequest unless matching_path
		json = "{ \"path\": \"#{matching_path}\" }"
		response.status = 200
		response['Content-Type'] = "application/json"
		response.body = json
	end
end

########################################
# This doesn't really do a whole lot
# We could however do something with the description
# That gets posted after the upload finished 
class FileUploadDescription < HTTPServlet::AbstractServlet
	def do_POST(request, response)
		# will be an array with a single string inside -> to_s
		uid = request.query['uid'].to_s
		raise HTTPStatus::BadRequest if uid.empty?
		description = request.query['description'].to_s
		# this would be the place to do something with the description
		puts "Received a description: #{description}"
		response.status = 200
		response['Content-Type'] = "application/json"
		response.body = '{}'
	end
end

# new server
server = HTTPServer.new(:Port => 1337)
# make sure we can kill the server using ctrl + c
['INT', 'TERM'].each { |signal| trap(signal) { server.shutdown } }

# We have to register our template extension, 
# otherwise we end up with an octet-stream
HTTPUtils::DefaultMimeTypes.store('rhtml', 'text/html')

# mount the servlets on their respective paths
server.mount "/", HTTPServlet::FileHandler, '.'
server.mount "/upload", FileUpload
server.mount "/progress", FileUploadProgress
server.mount "/filepath", FileUploadPath
server.mount "/description", FileUploadDescription

server.start