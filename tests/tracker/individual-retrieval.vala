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

public class IndividualRetrievalTests : Folks.TestCase
{
  private GLib.MainLoop _main_loop;
  private IndividualAggregator _aggregator;
  private TrackerTest.Backend _tracker_backend;
  private Gee.HashMap<string, string> _c1;
  private Gee.HashMap<string, string> _c2;

  public IndividualRetrievalTests ()
    {
      base ("IndividualRetrieval");

      this._tracker_backend = new TrackerTest.Backend ();

      this.add_test ("singleton individuals", this.test_singleton_individuals);
    }

  public override void set_up ()
    {
    }

  public override void tear_down ()
    {
    }

  public void test_singleton_individuals ()
    {
      this._main_loop = new GLib.MainLoop (null, false);
      this._c1 = new Gee.HashMap<string, string> ();
      this._c2 = new Gee.HashMap<string, string> ();

      this._c1.set (Trf.OntologyDefs.NCO_FULLNAME, "persona #1");
      this._tracker_backend.add_contact (this._c1);
      this._c2.set (Trf.OntologyDefs.NCO_FULLNAME, "persona #2");
      this._tracker_backend.add_contact (this._c2);
      this._tracker_backend.set_up ();

      this._test_singleton_individuals_async ();

      Timeout.add_seconds (5, () =>
        {
          this._main_loop.quit ();
          assert_not_reached ();
        });

      this._main_loop.run ();

      assert (this._c1.size == 0);
      assert (this._c2.size == 0);

      this._tracker_backend.tear_down ();
    }

  private async void _test_singleton_individuals_async ()
    {
      var store = BackendStore.dup ();
      yield store.prepare ();
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
          string full_name = ((Folks.NameDetails) i).full_name;
          if (full_name != null)
            {
              if (this._c1.get (Trf.OntologyDefs.NCO_FULLNAME) == full_name)
                {
                  this._c1.unset (Trf.OntologyDefs.NCO_FULLNAME);
                }

              if (this._c2.get (Trf.OntologyDefs.NCO_FULLNAME) == full_name)
                {
                  this._c2.unset (Trf.OntologyDefs.NCO_FULLNAME);
                }
            }
        }

        if (this._c1.size == 0 &&
            this._c2.size == 0)
          this._main_loop.quit ();

        assert (removed.size == 0);
    }
}

public int main (string[] args)
{
  Test.init (ref args);

  TestSuite root = TestSuite.get_root ();
  root.add_suite (new IndividualRetrievalTests ().get_suite ());

  Test.run ();

  return 0;
}
