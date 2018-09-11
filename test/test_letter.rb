# Copyright (c) 2018 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'rack/test'
require 'yaml'
require 'tmpdir'
require 'gserver'
require 'fakesmtpd'
require 'timeout'
require_relative 'test__helper'
require_relative '../objects/lanes'
require_relative '../objects/letters'
require_relative '../objects/lists'
require_relative '../objects/campaigns'

class LetterTest < Minitest::Test
  def test_sets_active_to_false
    owner = random_owner
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letters = Letters.new(lane: lane)
    letter = letters.add
    assert_equal(false, letter.active?)
  end

  def test_toggles_active_status
    owner = random_owner
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letters = Letters.new(lane: lane)
    letter = letters.add
    letter.toggle
    assert_equal(true, letter.active?)
    letter.toggle
    assert_equal(false, letter.active?)
  end

  def test_creates_and_updates_letter
    owner = random_owner
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letters = Letters.new(lane: lane)
    letter = letters.add('Hi, dude!')
    %w[first second third].each do |text|
      letter.save_yaml("test: #{text}")
      assert_equal(text, letter.yaml['test'])
      letter.save_liquid(text)
      assert_equal(text, letter.liquid)
    end
  end

  def test_updates_letter_from_fetch
    owner = random_owner
    lanes = Lanes.new(owner: owner)
    lane = lanes.add
    letters = Letters.new(lane: lane)
    letters.add
    letter = letters.all[0]
    %w[first second third].each do |text|
      letter.save_yaml("test: #{text}")
      assert_equal(text, letter.yaml['test'])
      letter.save_liquid(text)
      assert_equal(text, letter.liquid)
    end
  end

  def test_fetches_campaigns
    owner = random_owner
    list = Lists.new(owner: owner).add
    list.recipients.add('test@mailanes.com')
    lane = Lanes.new(owner: owner).add
    campaign = Campaigns.new(owner: owner).add(list, lane)
    campaign.toggle
    letter = lane.letters.add
    assert_equal(1, letter.campaigns.count)
  end

  def test_sends_via_smtp
    owner = random_owner
    list = Lists.new(owner: owner).add
    recipient = list.recipients.add('test11@mailanes.com')
    lane = Lanes.new(owner: owner).add
    letter = lane.letters.add
    port = random_port
    Dir.mktmpdir do |dir|
      smtpd = FakeSMTPd::Runner.new(
        dir: File.join(dir, 'messages'),
        port: port,
        logfile: File.join(dir, 'smtpd.log'),
        pidfile: File.join(dir, 'smtpd.pid')
      )
      letter.save_yaml(
        [
          'from: test@mailanes.com',
          'smtp:',
          '  host: localhost',
          "  port: #{port}",
          '  user: test',
          '  password: test'
        ].join("\n")
      )
      begin
        smtpd.start
        Timeout.timeout(5) do
          letter.deliver(recipient)
        end
      ensure
        smtpd.stop
      end
    end
  end

  def test_sends_via_telegram
    owner = random_owner
    list = Lists.new(owner: owner).add
    recipient = list.recipients.add('tes-t11@mailanes.com')
    lane = Lanes.new(owner: owner).add
    lane.save_yaml(
      [
        'telegram:',
        '  chat_id: 0'
      ].join("\n")
    )
    tbot = Tbot::Fake.new
    letter = lane.letters.add('some title', tbot: tbot)
    letter.save_liquid('How are you?')
    letter.save_yaml(
      [
        'transport: telegram'
      ].join("\n")
    )
    letter.deliver(recipient)
    assert_equal(1, tbot.sent.count)
    assert(tbot.sent[0].include?('How are you?'))
  end
end
