/*
 * Copyright (C) 2011 Collabora Ltd.
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors: Raul Gutierrez Segales <raul.gutierrez.segales@collabora.co.uk>
 *
 */

using Tracker.Sparql;
using TrackerTest;
using Folks;
using Gee;

public class BirthdayUpdatesTests : Folks.TestCase
{
  private TrackerTest.Backend _tracker_backend;
  private IndividualAggregator _aggregator;
  private string _initial_birthday;
  private string _updated_birthday;
  private string _individual_id;
  private bool _initial_birthday_found;
  private bool _updated_birthday_found;
  private string _contact_urn;
  private DateTime _initial_bday_obj;
  private DateTime _updated_bday_obj;
  private string _initial_fullname;
  private GLib.MainLoop _main_loop;

  public BirthdayUpdatesTests ()
    {
      base ("BirthdayUpdates");

      this._tracker_backend = new TrackerTest.Backend ();
      this._tracker_backend.debug = false;

      this.add_test ("birthday updates", this.test_birthday_updates);
    }

  public override void set_up ()
    {
    }

  public override void tear_down ()
    {
    }

  public void test_birthday_updates ()
    {
      this._main_loop = new GLib.MainLoop (null, false);
      Gee.HashMap<string, string> c1 = new Gee.HashMap<string, string> ();
      this._initial_fullname = "persona #1";
      this._initial_birthday = "2001-10-26T20:32:52Z";
      this._updated_birthday = "1991-10-26T20:32:52Z";
      this._contact_urn = "<urn:contact001>";

      TimeVal t1 = TimeVal ();
      t1.from_iso8601 (this._initial_birthday);
      this._initial_bday_obj = new  DateTime.from_timeval_utc (t1);

      TimeVal t2 = TimeVal ();
      t2.from_iso8601 (this._updated_birthday);
      this._updated_bday_obj = new  DateTime.from_timeval_utc (t2);

      c1.set (TrackerTest.Backend.URN, this._contact_urn);
      c1.set (Trf.OntologyDefs.NCO_FULLNAME, this._initial_fullname);
      c1.set (Trf.OntologyDefs.NCO_BIRTHDAY, this._initial_birthday);
      this._tracker_backend.add_contact (c1);

      this._tracker_backend.set_up ();

      this._initial_birthday_found = false;
      this._updated_birthday_found = false;
      this._individual_id = "";

      test_birthday_updates_async ();


      Timeout.add_seconds (5, () =>
        {
          this._main_loop.quit ();
          assert_not_reached ();
        });

      this._main_loop.run ();

      assert (this._initial_birthday_found == true);
      assert (this._updated_birthday_found == true);

      this._tracker_backend.tear_down ();
    }

  private async void test_birthday_updates_async ()
    {
      var store = BackendStore.dup ();
      yield store.prepare ();
      /* Set up the aggregator */
      this._aggregator = new IndividualAggregator ();
      this._aggregator.individuals_changed.connect
          (this._individuals_changed_cb);
      try
        {
          yield this._aggregator.prepare ();
        }
      catch (GLib.Error e)
        {
          GLib.warning ("Error when calling prepare: %s\n", e.message);
        }
    }

  private void _individuals_changed_cb
      (Set<Individual> added,
       Set<Individual> removed,
       string? message,
       Persona? actor,
       GroupDetails.ChangeReason reason)
    {
      foreach (var i in added)
        {
          if (i.full_name == this._initial_fullname)
            {
              i.notify["birthday"].connect (this._notify_birthday_cb);
              if (i.birthday != null &&
                  i.birthday.compare (this._initial_bday_obj) == 0)
                {
                  this._individual_id = i.id;
                  this._initial_birthday_found = true;
                  this._tracker_backend.update_contact (this._contact_urn,
                      Trf.OntologyDefs.NCO_BIRTHDAY, this._updated_birthday);
                }
            }
        }
        assert (removed.size == 0);
    }

  void _notify_birthday_cb (Object individual_obj, ParamSpec ps)
    {
      Folks.Individual i = (Folks.Individual) individual_obj;

      if (i.birthday == null)
        {
          return;
        }

      if (i.birthday.compare (this._initial_bday_obj) == 0)
        {
          this._individual_id = i.id;
          this._initial_birthday_found = true;
          this._tracker_backend.update_contact (this._contact_urn,
              Trf.OntologyDefs.NCO_BIRTHDAY, this._updated_birthday);
        }
      else if (i.birthday.compare (this._updated_bday_obj) == 0)
        {
          this._updated_birthday_found = true;
          this._main_loop.quit ();
        }
    }
}

public int main (string[] args)
{
  Test.init (ref args);

  TestSuite root = TestSuite.get_root ();
  root.add_suite (new BirthdayUpdatesTests ().get_suite ());

  Test.run ();

  return 0;
}
