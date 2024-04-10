# Drecs

Drecs is a teeny tiny barebones ecs implementation for [DragonRuby](https://dragonruby.org/toolkit/game)

## Installation

While there's no formal package manager for DragonRuby, you can use `$gtk.download_stb_rb("https://github.com/joshleblanc/drecs/blob/master/lib/drecs.rb")` to pull down the code into your project.

## Usage

Simply `require "joshleblanc/drecs/drecs.rb"` at the top of your `main.rb`.

There are two ways of including Drecs in your project

* If you're not using a Game class, use `include Drecs::Main` to include everything at the top level
* If you're using a Game class, use `include Drecs` in the class to include the appropriate class/instance methods

## Development

Samples are available in the samples directory. We use [drakkon](https://gitlab.com/dragon-ruby/drakkon) to manage the DragonRuby version. With drakkon installed, use `drakkon run` to run the sample.

The drecs library is copied into the `lib` folder of the samples. You can create a Junction with the main lib folder on windows using `New-Item -ItemType Junction -Path lib -Target ..\..\lib` from within the sample app directory. This will let you modify drecs.rb in one place.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/drecs. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Drecs project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).
