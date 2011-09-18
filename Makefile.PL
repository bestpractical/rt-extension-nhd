use inc::Module::Install;

RTx('RT-Extension-NHD');
all_from('lib/RT/Extension/NHD.pm');
#readme_from('lib/RT/Extension/NHD.pm');

WriteAll;