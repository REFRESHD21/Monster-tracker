Pod::Spec.new do |s|
  s.name = 'backup_destination'
  s.version = '1.0.0'
  s.summary = 'Verified user-selected backup folder copies.'
  s.description = 'Copies encrypted backups using document-provider access and verifies readback.'
  s.homepage = 'https://github.com/REFRESHD21/Monster-tracker'
  s.license = { :type => 'Proprietary' }
  s.author = { 'Business Tracker' => 'https://github.com/REFRESHD21' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.5'
  s.swift_version = '5.0'
end
