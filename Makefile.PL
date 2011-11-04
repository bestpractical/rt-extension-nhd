use inc::Module::Install;

RTx('RT-Extension-NetworkedHelpDesk');
all_from('lib/RT/Extension/NetworkedHelpDesk.pm');
readme_from('lib/RT/Extension/NetworkedHelpDesk.pm');

WriteAll;